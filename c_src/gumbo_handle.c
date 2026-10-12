#include <string.h>

#include <erl_nif.h>

#include "gumbo.h"
#include "gumbo_handle.h"
#include "gumbo_options.h"
#include "gumbo_parse_stack.h"

static ErlNifResourceType* gumbo_handle_resource_type = NULL;

/* The children vector per node type. GUMBO_NODE_TEMPLATE's v is a
   GumboElement, so it shares the element branch; every other type is a
   leaf. Shared with gumbo_node.c, which indexes children by table index. */
GumboVector* gumbo_node_children(GumboNode* node) {
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
    /* The walk inside is the one thing we patch, so it is the one thing that can
       lose its safety net quietly: destroy_node is iterative as of
       c_src/patches/0001, which is what makes this call safe on this thread at
       any depth, whatever its stack. c_src/test/teardown_probe.c holds it to that
       in both directions — the allocator balances to zero, and a 20 000-level
       tree survives a 320 KB stack. */
    gumbo_destroy_output(&h->options, h->output);
  }
  enif_free(h->nodes);
  enif_free(h->parent_indices);
  enif_free(h->subtree_sizes);
  /* The input binary's owner is the term in this env, so freeing the env is
     what releases it; it must not also be released by hand. Safe last:
     nothing in the teardown pass reads h->input. */
  if (h->env != NULL) {
    enif_free_env(h->env);
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
                   ERL_NIF_TERM index_term, gumbo_handle_t** handle_out,
                   GumboNode** out) {
  if (!gumbo_handle_get(env, handle_term, handle_out)) {
    return GUMBO_NODE_INVALID_HANDLE;
  }
  unsigned long index;
  if (!enif_get_ulong(env, index_term, &index)) {
    return GUMBO_NODE_INVALID_NODE;
  }
  if (index >= (*handle_out)->node_count) {
    return GUMBO_NODE_INVALID_NODE;
  }
  *out = (*handle_out)->nodes[index];
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
   and the document's first child follows it, whatever that is. Growth is
   geometric. Resolves h->root_index by pointer at the end, because
   output->root is NOT necessarily index 1: a comment or processing
   instruction before <html> is appended to the document's children first
   (parser.c:2390-2392 then append_node at :864-877), so the html element
   lands later in preorder. */
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

  /* Resolve by pointer rather than assuming: output->root is the document's
     first <html> element, but a comment or PI before it shifts it past
     index 1. A NULL output->root is legitimate — stop_on_first_error halts
     before any element exists (parser.c:513) — and becomes GUMBO_NO_ROOT;
     the errors vector is the whole point of stopping that early, so the
     parse must not fail. A non-NULL root missing from the table cannot
     happen — the walk starts at the document and visits every descendant —
     but a silent 0 would corrupt every root consumer, so fail the build. */
  if (h->output->root == NULL) {
    h->root_index = GUMBO_NO_ROOT;
    return 0;
  }
  size_t i;
  for (i = 0; i < h->node_count; ++i) {
    if (h->nodes[i] == h->output->root) {
      h->root_index = i;
      return 0;
    }
  }
  return 1;
}

/* Second pass over the finished table, filling the two index-arithmetic
   arrays the node accessors use: parent_indices[i] is the table index of
   nodes[i]'s parent (GUMBO_NO_PARENT for the document) and subtree_sizes[i]
   is the size of the subtree rooted at nodes[i]. The stack holds the indices
   of open subtrees, i.e. the ancestor chain of the node at index i, so when
   node i is not a child of the stack top, that top's subtree ended at i.
   Iterative and O(node_count): same no-recursion rule as the build. */
int gumbo_node_table_size(gumbo_handle_t* h) {
  size_t n = h->node_count;
  size_t* stack = enif_alloc((n + 1) * sizeof(size_t));
  h->parent_indices = enif_alloc(n * sizeof(size_t));
  h->subtree_sizes = enif_alloc(n * sizeof(size_t));
  if (stack == NULL || h->parent_indices == NULL || h->subtree_sizes == NULL) {
    enif_free(stack);
    enif_free(h->parent_indices);
    enif_free(h->subtree_sizes);
    h->parent_indices = NULL;
    h->subtree_sizes = NULL;
    return 1;
  }

  size_t sp = 0;
  size_t i;
  for (i = 0; i < n; ++i) {
    GumboNode* parent = h->nodes[i]->parent;
    while (sp > 0 && h->nodes[stack[sp - 1]] != parent) {
      --sp;
      h->subtree_sizes[stack[sp]] = i - stack[sp];
    }
    h->parent_indices[i] = (sp > 0) ? stack[sp - 1] : GUMBO_NO_PARENT;
    stack[sp++] = i;
  }
  while (sp > 0) {
    --sp;
    h->subtree_sizes[stack[sp]] = n - stack[sp];
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
    return enif_make_badarg(env);
  }
  /* The destructor is safe on a partially constructed handle because it
     releases only what this zeroing leaves set. */
  memset(h, 0, sizeof(*h));

  /* The env comes first, so that every failure path below — and the
     destructor — releases the retained copy by freeing this env. */
  h->env = enif_alloc_env();
  if (h->env == NULL) {
    enif_release_resource(h);
    return enif_make_badarg(env);
  }

  /* Private copy of the input, allocated in the env so that it can parent
     sub-binaries (see gumbo_handle.h). One extra byte is set to NUL: the
     error caret diagnostic walks to the first NUL (error.c's
     find_last_newline/find_next_newline), so the copy must be terminated
     exactly as gumbo's own printer expects. input_size stays the caller's
     byte count; the terminator is never parsed. */
  unsigned char* input_bytes =
      enif_make_new_binary(h->env, caller.size + 1, &h->input_term);
  if (input_bytes == NULL) {
    enif_release_resource(h);
    return enif_make_badarg(env);
  }
  h->input_data = (const char*)input_bytes;
  h->input_size = caller.size;
  if (caller.size > 0) {
    memcpy(input_bytes, caller.data, caller.size);
  }
  input_bytes[caller.size] = '\0';

  if (!gumbo_options_decode(env, atoms, argv[1], h)) {
    enif_release_resource(h);
    return enif_make_tuple2(env, atoms->error, atoms->invalid_option);
  }

  /* Never gumbo_parse: Elixir binaries are not NUL-terminated. Nor
     gumbo_parse_with_options directly: its recursion follows the input's
     nesting depth, so the parse needs a stack sized for the worst case the
     length can produce — see gumbo_parse_stack.c. */
  gumbo_parse_stack_status_t parse_status = GUMBO_PARSE_STACK_OK;
  h->output = gumbo_parse_on_sized_stack(&h->options, h->input_data,
                                         h->input_size, &parse_status);
  if (parse_status == GUMBO_PARSE_STACK_TOO_LARGE) {
    /* Checked on the Elixir side first, against the same limit; this is the
       backstop, so the two can never disagree about what is parseable. */
    enif_release_resource(h);
    return enif_make_tuple2(env, atoms->error, atoms->input_too_large);
  }
  if (h->output == NULL) {
    enif_release_resource(h);
    return enif_make_badarg(env);
  }

  if (gumbo_node_table_build(h) != 0) {
    /* The table is the handle's index — the node accessors read it — so a
       partial one makes the handle unusable, but not the tree: destroy_node is
       iterative as of c_src/patches/0001, so gumbo_destroy_output frees all of it
       at any depth, exactly as the destructor does. Unreachable in practice (OOM,
       or a non-NULL output->root missing from the table) and the parse raises
       either way. */
    gumbo_destroy_output(&h->options, h->output);
    h->output = NULL;
    enif_release_resource(h);
    return enif_make_badarg(env);
  }
  if (gumbo_node_table_size(h) != 0) {
    /* Same unreachable OOM path as the table build: a partly filled parent/size
       pair would silently corrupt the node accessors' index arithmetic, so the
       handle is not usable — but the tree is still entirely ours to free. */
    gumbo_destroy_output(&h->options, h->output);
    h->output = NULL;
    enif_release_resource(h);
    return enif_make_badarg(env);
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
  /* Resolved by pointer during the table build, not assumed to be 1: a
     comment or PI before <html> sits at index 1 instead, and a parse that
     stopped before any element has no root at all. */
  if (h->root_index == GUMBO_NO_ROOT) {
    return atoms->nil;
  }
  return enif_make_ulong(env, (unsigned long)h->root_index);
}

ERL_NIF_TERM gumbo_nif_output_input(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  if (!gumbo_handle_get(env, argv[0], &h)) {
    return enif_make_tuple2(env, atoms->error, atoms->invalid_handle);
  }
  /* A copy of exactly the input: input_term is one byte longer, because it
     carries the NUL the caret diagnostic needs, so the term itself would
     round-trip with a trailing byte the caller never passed. */
  ERL_NIF_TERM out;
  if (!gumbo_make_binary(env, h->input_data, h->input_size, &out)) {
    return enif_make_badarg(env);
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
    return enif_make_badarg(env);
  }
  return out;
}
