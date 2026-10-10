#include <string.h>

#include <erl_nif.h>

#include "attribute.h" /* gumbo_destroy_attribute */
#include "gumbo.h"
#include "gumbo_handle.h"
#include "gumbo_options.h"
#include "parser.h" /* GumboParser, for the destructor's stack-local parser */
#include "util.h"  /* gumbo_parser_deallocate */

/* parser.h and util.h are internal to gumbo-parser and are depended on only
   for the destructor's stack-local GumboParser, exactly as
   gumbo_destroy_output and gumbo_destroy_node do. Acceptable because the
   submodule pins the version. */

static ErlNifResourceType* gumbo_handle_resource_type = NULL;

/* The children vector per node type. GUMBO_NODE_TEMPLATE's v is a
   GumboElement, so it shares the element branch; every other type is a
   leaf. */
static GumboVector* gumbo_node_children(GumboNode* node) {
  switch (node->type) {
    case GUMBO_NODE_DOCUMENT:
      return &node->v.document.children;
    case GUMBO_NODE_ELEMENT:
    case GUMBO_NODE_TEMPLATE:
      return &node->v.element.children;
    default:
      return NULL;
  }
}

static void gumbo_handle_dtor(ErlNifEnv* env, void* obj) {
  (void)env;

  gumbo_handle_t* h = obj;
  if (h->output != NULL) {
    /* Teardown runs on a GC/scheduler thread, possibly on the dirty CPU
       scheduler's small stack, so it must not recurse. gumbo's own
       destroy_node recurses once per tree level and 0.14.1 has no nesting
       cap; its per-node work (spec: parser.c destroy_node at tag 0.14.1)
       is therefore reimplemented here iteratively in reverse preorder:
       preorder puts a parent before all its descendants, so descending
       index order frees every child before its parent.

       Emptying each children vector as we go also makes the destroy_node
       call inside gumbo_destroy_output bottom out at depth 1, where it
       frees only the document node, the doctype strings, the error vector
       and the output struct. Note: merely emptying the vectors is NOT
       enough — stopping destroy_node's loop also stops its traversal, so
       the whole subtree below the document would leak. This loop must
       stay in sync with c_src/test/teardown_probe.c, which asserts a
       counting allocator's balance is zero across the same teardown. */
    GumboParser parser;
    memset(&parser, 0, sizeof(parser));
    parser._options = &h->options;
    for (size_t i = h->node_count; i-- > 0;) {
      GumboNode* node = h->nodes[i];
      GumboVector* children = NULL;

      switch (node->type) {
        case GUMBO_NODE_ELEMENT:
        case GUMBO_NODE_TEMPLATE: {
          GumboVector* attributes = &node->v.element.attributes;
          unsigned int j;
          for (j = 0; j < attributes->length; ++j) {
            gumbo_destroy_attribute(&parser, attributes->data[j]);
          }
          gumbo_parser_deallocate(&parser, attributes->data);
          attributes->data = NULL;
          attributes->length = 0;
          attributes->capacity = 0;
          children = &node->v.element.children;
          break;
        }
        case GUMBO_NODE_DOCUMENT:
          children = &node->v.document.children;
          break;
        default: /* TEXT, CDATA, COMMENT, WHITESPACE, PROCESSING_INSTRUCTION */
          gumbo_parser_deallocate(&parser, (void*)node->v.text.text);
          break;
      }

      if (children != NULL) {
        /* Free the pointer array and zero all three fields by hand;
           gumbo_vector_destroy is not a substitute because it leaves
           length set, and the zeroed vector is what stops destroy_node's
           double-free in gumbo_destroy_output. */
        gumbo_parser_deallocate(&parser, children->data);
        children->data = NULL;
        children->length = 0;
        children->capacity = 0;
      }
      /* gumbo_destroy_output's destroy_node frees the document node
         itself; compare pointers rather than indices so this stays
         correct if the table build ever changes. */
      if (node != h->output->document) {
        gumbo_parser_deallocate(&parser, node);
      }
    }
    gumbo_destroy_output(&h->options, h->output);
  }
  enif_free(h->nodes);
  if (h->input.data != NULL) {
    enif_release_binary(&h->input);
  }
}

int gumbo_handle_init(ErlNifEnv* env) {
  gumbo_handle_resource_type = enif_open_resource_type(
      env, NULL, "gumbo_output", gumbo_handle_dtor, ERL_NIF_RT_CREATE, NULL);
  return gumbo_handle_resource_type == NULL ? 1 : 0;
}

int gumbo_handle_get(ErlNifEnv* env, ERL_NIF_TERM term,
                     gumbo_handle_t** out) {
  return enif_get_resource(env, term, gumbo_handle_resource_type,
                           (void**)out);
}

int gumbo_node_get(ErlNifEnv* env, ERL_NIF_TERM handle_term,
                   ERL_NIF_TERM index_term, GumboNode** out) {
  gumbo_handle_t* h;
  if (!gumbo_handle_get(env, handle_term, &h)) {
    return GUMBO_NODE_INVALID_HANDLE;
  }
  unsigned long index;
  if (!enif_get_ulong(env, index_term, &index)) {
    return GUMBO_NODE_INVALID_NODE;
  }
  if (index >= h->node_count) {
    return GUMBO_NODE_INVALID_NODE;
  }
  *out = h->nodes[index];
  return GUMBO_NODE_OK;
}

/* Explicit heap stack: pushes children in reverse so they pop in source
   order, giving a true preorder with no C recursion regardless of depth. */
static int gumbo_stack_push(GumboNode*** stack, size_t* count,
                            size_t* capacity, GumboNode* node) {
  if (*count == *capacity) {
    size_t next = (*capacity == 0) ? 64 : *capacity * 2;
    GumboNode** grown = enif_realloc(*stack, next * sizeof(GumboNode*));
    if (grown == NULL) {
      return 1;
    }
    *stack = grown;
    *capacity = next;
  }
  (*stack)[(*count)++] = node;
  return 0;
}

/* Flattens the tree into h->nodes in preorder: index 0 is the document node
   and index 1 is output->root. Growth is geometric. */
static int gumbo_node_table_build(gumbo_handle_t* h) {
  GumboNode** stack = NULL;
  size_t stack_count = 0;
  size_t stack_capacity = 0;

  if (h->output->document == NULL) {
    return 1; /* gumbo always creates one; this cannot happen */
  }
  if (gumbo_stack_push(&stack, &stack_count, &stack_capacity,
                       h->output->document) != 0) {
    enif_free(stack);
    return 1;
  }

  while (stack_count > 0) {
    GumboNode* node = stack[--stack_count];

    if (h->node_count == h->capacity) {
      size_t next = (h->capacity == 0) ? 16 : h->capacity * 2;
      GumboNode** nodes = enif_realloc(h->nodes, next * sizeof(GumboNode*));
      if (nodes == NULL) {
        enif_free(stack);
        return 1;
      }
      h->nodes = nodes;
      h->capacity = next;
    }
    h->nodes[h->node_count++] = node;

    GumboVector* children = gumbo_node_children(node);
    if (children != NULL) {
      unsigned int i;
      for (i = children->length; i-- > 0;) {
        if (gumbo_stack_push(&stack, &stack_count, &stack_capacity,
                             children->data[i]) != 0) {
          enif_free(stack);
          return 1;
        }
      }
    }
  }

  enif_free(stack);
  return 0;
}

ERL_NIF_TERM gumbo_nif_parse(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                             int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  ErlNifBinary caller;
  if (!enif_inspect_binary(env, argv[0], &caller)) {
    return enif_make_badarg(env);
  }

  gumbo_handle_t* h =
      enif_alloc_resource(gumbo_handle_resource_type, sizeof(gumbo_handle_t));
  if (h == NULL) {
    /* Allocation failure surfaces as an ArgumentError; it is unreachable in
       practice and this path must not create atoms. */
    return enif_raise_exception(env, enif_make_badarg(env));
  }
  /* The destructor is safe on a partially constructed handle because it
     releases only what this zeroing leaves set. */
  memset(h, 0, sizeof(*h));

  /* Private copy of the input: the tree's original_text/original_tag/...
     fields point into it, and the caller's binary is not safe to hold. */
  if (!enif_alloc_binary(caller.size, &h->input)) {
    enif_release_resource(h);
    return enif_raise_exception(env, enif_make_badarg(env));
  }
  if (caller.size > 0) {
    memcpy(h->input.data, caller.data, caller.size);
  }

  if (!gumbo_options_decode(env, atoms, argv[1], h)) {
    enif_release_resource(h);
    return enif_make_tuple2(env, atoms->error, atoms->invalid_option);
  }

  /* Never gumbo_parse: Elixir binaries are not NUL-terminated. */
  h->output = gumbo_parse_with_options(&h->options, (const char*)h->input.data,
                                       h->input.size);
  if (h->output == NULL) {
    enif_release_resource(h);
    return enif_raise_exception(env, enif_make_badarg(env));
  }

  if (gumbo_node_table_build(h) != 0) {
    /* The table only partially covers the tree, so the teardown above
       cannot empty every children vector and destroy_node inside
       gumbo_destroy_output would still recurse into unvisited subtrees
       on a GC thread. This is an unreachable OOM path, and the parse
       already raises; leak the tree rather than risk that recursion. */
    h->output = NULL;
    enif_release_resource(h);
    return enif_raise_exception(env, enif_make_badarg(env));
  }

  ERL_NIF_TERM resource = enif_make_resource(env, h);
  enif_release_resource(h);
  return enif_make_tuple2(env, atoms->ok, resource);
}

ERL_NIF_TERM gumbo_nif_output_document(ErlNifEnv* env,
                                       const gumbo_atoms_t* atoms, int argc,
                                       const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  if (!gumbo_handle_get(env, argv[0], &h)) {
    return enif_make_tuple2(env, atoms->error, atoms->invalid_handle);
  }
  /* The table is built in preorder from output->document, so the document
     node is always index 0. */
  return enif_make_int(env, 0);
}

ERL_NIF_TERM gumbo_nif_output_root(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                   int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  if (!gumbo_handle_get(env, argv[0], &h)) {
    return enif_make_tuple2(env, atoms->error, atoms->invalid_handle);
  }
  /* ... and its first child, output->root (the real or implied <html>), is
     always index 1. */
  return enif_make_int(env, 1);
}

ERL_NIF_TERM gumbo_nif_output_input(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  if (!gumbo_handle_get(env, argv[0], &h)) {
    return enif_make_tuple2(env, atoms->error, atoms->invalid_handle);
  }
  ERL_NIF_TERM out;
  if (!gumbo_make_binary(env, (const char*)h->input.data, h->input.size,
                         &out)) {
    return enif_raise_exception(env, enif_make_badarg(env));
  }
  return out;
}

ERL_NIF_TERM gumbo_nif_output_node_count(ErlNifEnv* env,
                                         const gumbo_atoms_t* atoms, int argc,
                                         const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  if (!gumbo_handle_get(env, argv[0], &h)) {
    return enif_make_tuple2(env, atoms->error, atoms->invalid_handle);
  }
  return enif_make_ulong(env, (unsigned long)h->node_count);
}

ERL_NIF_TERM gumbo_nif_output_options(ErlNifEnv* env,
                                      const gumbo_atoms_t* atoms, int argc,
                                      const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  if (!gumbo_handle_get(env, argv[0], &h)) {
    return enif_make_tuple2(env, atoms->error, atoms->invalid_handle);
  }
  ERL_NIF_TERM out;
  if (!gumbo_options_encode(env, atoms, h, &out)) {
    return enif_raise_exception(env, enif_make_badarg(env));
  }
  return out;
}
