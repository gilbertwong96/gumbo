#include "gumbo.h"
#include "gumbo_attr.h"
#include "gumbo_atoms.h"
#include "gumbo_error.h"
#include "gumbo_handle.h"
#include "gumbo_materialize.h"
#include "gumbo_node.h"

/* This file owns the two materialize NIFs. Both walk the handle's preorder
   node table in a single reverse loop, assembling each node's map from its
   already-built children and storing the terms in a scratch ERL_NIF_TERM[]
   of node_count entries. The load-bearing property is preorder: it places a
   parent before all of its descendants, so descending table order builds
   every child before its parent and no children list ever reads an unbuilt
   term — depth costs memory, never C stack, and nothing here recurses.

   The scalar fields come from gumbo_node.c's exported extractors, the same
   functions node_details uses, so a value cannot be right in the lazy
   surface and wrong in the materialized one. Only the key names differ
   where the materialized shape renames them: :position -> :start_position
   and :doctype_name -> :name, per the design's :full shape. Attribute maps
   reuse gumbo_attr_details_map and error maps gumbo_error_details_map,
   likewise one builder per surface.

   Every term is built in the caller's environment per call; atoms are
   immediates and the only terms that outlive a call. Allocation failure
   surfaces as an exception, the same contract the extractors already
   keep. */

#define GUMBO_DETAIL_FULL 0
#define GUMBO_DETAIL_CONTENT 1

/* The children list of the node at table index i, whose subtree is the
   range [i, i + subtree_sizes[i]). Preorder makes siblings contiguous:
   child 0 starts at i + 1 and each next child starts right after the
   previous child's subtree, so the walk needs only subtree_sizes — no
   pointer-to-index lookup, which is why no child-index structure is
   needed. scratch holds the child terms transiently; it is shared across
   the whole walk because the list cells copy them. */
static ERL_NIF_TERM gumbo_materialize_children(ErlNifEnv* env,
                                               const gumbo_handle_t* h,
                                               size_t i,
                                               const ERL_NIF_TERM* terms,
                                               ERL_NIF_TERM* scratch) {
  ERL_NIF_TERM list = enif_make_list(env, 0);
  GumboVector* children = gumbo_node_children(h->nodes[i]);
  if (children == NULL || children->length == 0) {
    return list;
  }

  size_t end = i + h->subtree_sizes[i];
  size_t n = 0;
  size_t c = i + 1;
  while (c < end) {
    scratch[n++] = terms[c];
    c += h->subtree_sizes[c];
  }
  /* Cons from the end so the list comes out in source order. */
  while (n-- > 0) {
    list = enif_make_list_cell(env, scratch[n], list);
  }
  return list;
}

/* :full — a list with one map per attribute, built by the same builder
   attr_details uses. :content — %{name => value} built with
   enif_make_map_put, whose overwrite-on-repeated-key semantics match
   Gumbo.Node.attribute_map/1's Map.new; gumbo itself records duplicate
   names as errors and keeps only the first, so the two surfaces agree. */
static ERL_NIF_TERM gumbo_materialize_attributes(ErlNifEnv* env,
                                                 const gumbo_atoms_t* atoms,
                                                 GumboNode* node,
                                                 int detail) {
  GumboVector* attributes = &node->v.element.attributes;
  if (detail == GUMBO_DETAIL_CONTENT) {
    ERL_NIF_TERM map = enif_make_new_map(env);
    unsigned int i;
    for (i = 0; i < attributes->length; ++i) {
      GumboAttribute* attr = attributes->data[i];
      ERL_NIF_TERM name = gumbo_node_stringz(env, atoms, attr->name);
      ERL_NIF_TERM value = gumbo_node_stringz(env, atoms, attr->value);
      if (!enif_make_map_put(env, map, name, value, &map)) {
        return enif_make_badarg(env);
      }
    }
    return map;
  }

  ERL_NIF_TERM list = enif_make_list(env, 0);
  unsigned int i;
  for (i = attributes->length; i-- > 0;) {
    ERL_NIF_TERM map;
    if (!gumbo_attr_details_map(env, atoms, attributes->data[i], &map)) {
      return enif_make_badarg(env);
    }
    list = enif_make_list_cell(env, map, list);
  }
  return list;
}

/* The :content shape: a usable tree with no source bookkeeping. Elements
   and templates carry %{type, tag, namespace, attributes, children},
   text-like nodes %{type, text}, and the document node %{type, children} —
   it owns the walk's entry points and nothing else. */
static ERL_NIF_TERM gumbo_materialize_node_content(ErlNifEnv* env,
                                                   const gumbo_atoms_t* atoms,
                                                   GumboNode* node,
                                                   ERL_NIF_TERM children) {
  switch (node->type) {
    case GUMBO_NODE_DOCUMENT: {
      ERL_NIF_TERM keys[] = {atoms->node.type, atoms->node.children};
      ERL_NIF_TERM values[] = {atoms->node_types[node->type], children};
      ERL_NIF_TERM map;
      if (!enif_make_map_from_arrays(env, keys, values, 2, &map)) {
        return enif_make_badarg(env);
      }
      return map;
    }
    case GUMBO_NODE_ELEMENT:
    case GUMBO_NODE_TEMPLATE: {
      ERL_NIF_TERM attributes =
          gumbo_materialize_attributes(env, atoms, node, GUMBO_DETAIL_CONTENT);
      ERL_NIF_TERM keys[] = {atoms->node.type, atoms->node.tag,
                             atoms->node.namespace, atoms->node.attributes,
                             atoms->node.children};
      ERL_NIF_TERM values[] = {atoms->node_types[node->type],
                               atoms->tags[node->v.element.tag],
                               atoms->namespaces[node->v.element.tag_namespace],
                               attributes, children};
      ERL_NIF_TERM map;
      if (!enif_make_map_from_arrays(env, keys, values, 5, &map)) {
        return enif_make_badarg(env);
      }
      return map;
    }
    default: {
      ERL_NIF_TERM keys[] = {atoms->node.type, atoms->node.text};
      ERL_NIF_TERM values[] = {atoms->node_types[node->type],
                               gumbo_node_text_term(env, atoms, node)};
      ERL_NIF_TERM map;
      if (!enif_make_map_from_arrays(env, keys, values, 2, &map)) {
        return enif_make_badarg(env);
      }
      return map;
    }
  }
}

#define GUMBO_MATERIALIZE_FULL_COUNT 19

/* The :full shape: every gumbo field, with nil where the node type carries
   none — the extractors answer nil off their types, exactly as the lazy
   accessors do — plus the attributes list and the children list. */
static ERL_NIF_TERM gumbo_materialize_node_full(ErlNifEnv* env,
                                                const gumbo_atoms_t* atoms,
                                                GumboNode* node,
                                                ERL_NIF_TERM children) {
  ERL_NIF_TERM attributes =
      gumbo_node_is_element(node)
          ? gumbo_materialize_attributes(env, atoms, node, GUMBO_DETAIL_FULL)
          : enif_make_list(env, 0);

  ERL_NIF_TERM keys[GUMBO_MATERIALIZE_FULL_COUNT] = {
      atoms->node.type,
      atoms->node.index_within_parent,
      atoms->node.parse_flags,
      atoms->node.start_position,
      atoms->node.has_doctype,
      atoms->node.name,
      atoms->node.public_identifier,
      atoms->node.system_identifier,
      atoms->node.quirks_mode,
      atoms->node.tag,
      atoms->node.tag_name,
      atoms->node.namespace,
      atoms->node.original_tag,
      atoms->node.original_end_tag,
      atoms->node.end_position,
      atoms->node.text,
      atoms->node.original_text,
      atoms->node.attributes,
      atoms->node.children,
  };
  ERL_NIF_TERM values[GUMBO_MATERIALIZE_FULL_COUNT] = {
      gumbo_node_type_term(env, atoms, node),
      gumbo_node_index_within_parent_term(env, atoms, node),
      gumbo_node_parse_flags_term(env, atoms, node),
      gumbo_node_position_term(env, atoms, node),
      gumbo_node_has_doctype_term(env, atoms, node),
      gumbo_node_doctype_name_term(env, atoms, node),
      gumbo_node_public_identifier_term(env, atoms, node),
      gumbo_node_system_identifier_term(env, atoms, node),
      gumbo_node_quirks_mode_term(env, atoms, node),
      gumbo_node_tag_term(env, atoms, node),
      gumbo_node_tag_name_term(env, atoms, node),
      gumbo_node_namespace_term(env, atoms, node),
      gumbo_node_original_tag_term(env, atoms, node),
      gumbo_node_original_end_tag_term(env, atoms, node),
      gumbo_node_end_position_term(env, atoms, node),
      gumbo_node_text_term(env, atoms, node),
      gumbo_node_original_text_term(env, atoms, node),
      attributes,
      children,
  };
  ERL_NIF_TERM map;
  if (!enif_make_map_from_arrays(env, keys, values,
                                 GUMBO_MATERIALIZE_FULL_COUNT, &map)) {
    return enif_make_badarg(env);
  }
  return map;
}

/* One reverse pass over the table range [start, start + count), storing
   each node's map at terms[i]. Children are read from positions greater
   than i, which the pass has already built; scratch is the shared
   child-terms buffer, allocated by gumbo_materialize_scratch to fit any
   children vector in the range. Allocation failures surface as badarg
   terms rather than raising. */
static void gumbo_materialize_range(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    const gumbo_handle_t* h, size_t start,
                                    size_t count, int detail,
                                    ERL_NIF_TERM* terms,
                                    ERL_NIF_TERM* scratch) {
  size_t i;
  for (i = start + count; i-- > start;) {
    GumboNode* node = h->nodes[i];
    ERL_NIF_TERM children =
        gumbo_materialize_children(env, h, i, terms, scratch);
    terms[i] = (detail == GUMBO_DETAIL_CONTENT)
                   ? gumbo_materialize_node_content(env, atoms, node, children)
                   : gumbo_materialize_node_full(env, atoms, node, children);
  }
}

/* The two scratch arrays every materialize call needs: the per-node terms
   and the shared children buffer. Each children vector has at most
   node_count - 1 entries and one is processed at a time, so node_count
   entries always fit. On allocation failure it frees both and returns 0;
   the callers answer badarg, which the VM surfaces as an ArgumentError. */
static int gumbo_materialize_scratch(size_t count, ERL_NIF_TERM** terms_out,
                                     ERL_NIF_TERM** scratch_out) {
  ERL_NIF_TERM* terms = enif_alloc(count * sizeof(ERL_NIF_TERM));
  ERL_NIF_TERM* scratch = enif_alloc(count * sizeof(ERL_NIF_TERM));
  if (terms == NULL || scratch == NULL) {
    enif_free(terms);
    enif_free(scratch);
    return 0;
  }
  *terms_out = terms;
  *scratch_out = scratch;
  return 1;
}

ERL_NIF_TERM gumbo_nif_materialize_output(ErlNifEnv* env,
                                          const gumbo_atoms_t* atoms,
                                          int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  if (!gumbo_handle_get(env, argv[0], &h)) {
    return enif_make_tuple2(env, atoms->error, atoms->invalid_handle);
  }
  int detail;
  if (!enif_get_int(env, argv[1], &detail) ||
      (detail != GUMBO_DETAIL_FULL && detail != GUMBO_DETAIL_CONTENT)) {
    return enif_make_badarg(env);
  }

  ERL_NIF_TERM* terms;
  ERL_NIF_TERM* scratch;
  if (!gumbo_materialize_scratch(h->node_count, &terms, &scratch)) {
    return enif_make_badarg(env);
  }

  gumbo_materialize_range(env, atoms, h, 0, h->node_count, detail, terms,
                          scratch);

  /* The errors vector in source order, each rendered by the same builder
     error_details/1 uses; the detail option does not apply to errors. */
  ERL_NIF_TERM errors = enif_make_list(env, 0);
  GumboVector* vector = &h->output->errors;
  unsigned int i;
  for (i = vector->length; i-- > 0;) {
    ERL_NIF_TERM map;
    if (!gumbo_error_details_map(env, atoms, h, vector->data[i], &map)) {
      enif_free(terms);
      enif_free(scratch);
      return enif_make_badarg(env);
    }
    errors = enif_make_list_cell(env, map, errors);
  }

  /* Table invariant: 0 is the document node, root_index is output->root —
     resolved by pointer at parse time, because a comment or PI before
     <html> occupies index 1 instead — or nil when the parse stopped
     before any element was built (GUMBO_NO_ROOT). */
  ERL_NIF_TERM keys[] = {atoms->materialize.document, atoms->materialize.root,
                         atoms->materialize.errors};
  ERL_NIF_TERM root =
      (h->root_index == GUMBO_NO_ROOT) ? atoms->nil : terms[h->root_index];
  ERL_NIF_TERM values[] = {terms[0], root, errors};
  ERL_NIF_TERM out;
  if (!enif_make_map_from_arrays(env, keys, values, 3, &out)) {
    enif_free(terms);
    enif_free(scratch);
    return enif_make_badarg(env);
  }
  enif_free(terms);
  enif_free(scratch);
  return out;
}

ERL_NIF_TERM gumbo_nif_materialize_node(ErlNifEnv* env,
                                        const gumbo_atoms_t* atoms, int argc,
                                        const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  GumboNode* node;
  if (gumbo_node_get(env, argv[0], argv[1], &h, &node) != GUMBO_NODE_OK) {
    /* The same invalid-node contract node_details keeps: a hand-built node
       with an out-of-range index is a {:error, :invalid_node}, never a
       dereference. */
    return enif_make_tuple2(env, atoms->error, atoms->node.invalid_node);
  }
  (void)node; /* the walk below re-resolves every position by index */

  int detail;
  if (!enif_get_int(env, argv[2], &detail) ||
      (detail != GUMBO_DETAIL_FULL && detail != GUMBO_DETAIL_CONTENT)) {
    return enif_make_badarg(env);
  }
  unsigned long index;
  if (!enif_get_ulong(env, argv[1], &index)) {
    return enif_make_badarg(env); /* unreachable: gumbo_node_get checked it */
  }

  /* Only the node's own subtree is walked, but the scratch arrays cover the
     whole table so positions stay absolute and the children walk shares one
     code path with materialize_output. */
  ERL_NIF_TERM* terms;
  ERL_NIF_TERM* scratch;
  if (!gumbo_materialize_scratch(h->node_count, &terms, &scratch)) {
    return enif_make_badarg(env);
  }

  size_t start = (size_t)index;
  gumbo_materialize_range(env, atoms, h, start, h->subtree_sizes[start],
                          detail, terms, scratch);
  ERL_NIF_TERM out = terms[start];
  enif_free(terms);
  enif_free(scratch);
  return enif_make_tuple2(env, atoms->ok, out);
}
