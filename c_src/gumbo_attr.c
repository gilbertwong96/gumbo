#include "gumbo_attr.h"

#include "gumbo.h"
#include "gumbo_faults.h"
#include "gumbo_handle.h"
#include "gumbo_node.h"

/* This file owns every scalar GumboAttribute field as one extractor each,
   plus attr_details, which assembles the full map from them. The extractors
   are the single source of truth, exactly as in gumbo_node.c, so a field
   cannot be right in one place and wrong in another; materialize reuses them
   through gumbo_attr_details_map. Every term is built in the caller's
   environment per call, and the string and position extractors are the same
   exported helpers gumbo_node.c uses, so a node field and an attribute field
   of the same shape follow the same code path.

   Failures are reported by the return value, never by a term: an extractor
   answers 1 with *out filled, or 0 with *out untouched, and the entry point
   turns a 0 into a badarg. A term that stands for a failure is a term a map
   cannot tell from a value, which is how a failed extraction once came back
   to a caller as a 42.

   Binding safety: attribute.c has no asserts, so unlike the tag and node
   files there is no gumbo precondition to guard here; the only rule is the
   bounds check an attribute index passes before it reaches the vector. */

/* Resolves (node, attribute index) to a GumboAttribute* with bounds
   checking: the node must carry an attribute vector and the index must be a
   non-negative integer inside it. Returns 1 on success. */
static int gumbo_attr_get(ErlNifEnv* env, ERL_NIF_TERM index_term,
                          GumboNode* node, GumboAttribute** out) {
  if (!gumbo_node_is_element(node)) {
    return 0;
  }
  unsigned long index;
  if (!enif_get_ulong(env, index_term, &index)) {
    return 0;
  }
  GumboVector* attributes = &node->v.element.attributes;
  if (index >= attributes->length) {
    return 0;
  }
  *out = attributes->data[index];
  return 1;
}

/* ---- one scalar extractor per field ---- */

static int gumbo_attr_namespace_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     const GumboAttribute* attr,
                                     ERL_NIF_TERM* out) {
#ifdef GUMBO_TEST_FAULTS
  if (gumbo_fault_should_fail()) {
    /* A failure, on purpose: see gumbo_faults.h. */
    return GUMBO_FAULT_FAILURE(env, out);
  }
#endif

  (void)env;
  /* Parser-produced, so the table index is in range by construction. */
  *out = atoms->attribute_namespaces[attr->attr_namespace];
  return 1;
}

static int gumbo_attr_name_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                const GumboAttribute* attr, ERL_NIF_TERM* out) {
  return gumbo_node_stringz(env, atoms, attr->name, out);
}

static int gumbo_attr_value_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                 const GumboAttribute* attr,
                                 ERL_NIF_TERM* out) {
  return gumbo_node_stringz(env, atoms, attr->value, out);
}

static int gumbo_attr_original_name_term(ErlNifEnv* env,
                                         const gumbo_atoms_t* atoms,
                                         const GumboAttribute* attr,
                                         ERL_NIF_TERM* out) {
  (void)atoms;
  return gumbo_node_string_piece(env, attr->original_name, out);
}

static int gumbo_attr_original_value_term(ErlNifEnv* env,
                                          const gumbo_atoms_t* atoms,
                                          const GumboAttribute* attr,
                                          ERL_NIF_TERM* out) {
  (void)atoms;
  return gumbo_node_string_piece(env, attr->original_value, out);
}

static int gumbo_attr_position_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    GumboSourcePosition pos,
                                    ERL_NIF_TERM* out) {
  return gumbo_node_position_map(env, atoms, pos, out);
}

static int gumbo_attr_name_start_term(ErlNifEnv* env,
                                      const gumbo_atoms_t* atoms,
                                      const GumboAttribute* attr,
                                      ERL_NIF_TERM* out) {
  return gumbo_attr_position_term(env, atoms, attr->name_start, out);
}

static int gumbo_attr_name_end_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    const GumboAttribute* attr,
                                    ERL_NIF_TERM* out) {
  return gumbo_attr_position_term(env, atoms, attr->name_end, out);
}

static int gumbo_attr_value_start_term(ErlNifEnv* env,
                                       const gumbo_atoms_t* atoms,
                                       const GumboAttribute* attr,
                                       ERL_NIF_TERM* out) {
  return gumbo_attr_position_term(env, atoms, attr->value_start, out);
}

static int gumbo_attr_value_end_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     const GumboAttribute* attr,
                                     ERL_NIF_TERM* out) {
#ifdef GUMBO_TEST_FAULTS
  if (gumbo_fault_should_fail()) {
    /* A failure, on purpose: see gumbo_faults.h. */
    return GUMBO_FAULT_FAILURE(env, out);
  }
#endif

  return gumbo_attr_position_term(env, atoms, attr->value_end, out);
}

/* ---- the NIF entry point ---- */

#define GUMBO_ATTR_DETAILS_COUNT 9

/* The full attribute map, shared by attr_details and materialize's :full
   attribute lists so the two surfaces cannot disagree. */
int gumbo_attr_details_map(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                           const GumboAttribute* attr, ERL_NIF_TERM* out) {
  ERL_NIF_TERM keys[GUMBO_ATTR_DETAILS_COUNT] = {
      atoms->attribute.namespace,      atoms->attribute.name,
      atoms->attribute.value,          atoms->attribute.original_name,
      atoms->attribute.original_value, atoms->attribute.name_start,
      atoms->attribute.name_end,       atoms->attribute.value_start,
      atoms->attribute.value_end,
  };
  ERL_NIF_TERM values[GUMBO_ATTR_DETAILS_COUNT];

  /* Each extraction is asked whether it succeeded. */
  if (!gumbo_attr_namespace_term(env, atoms, attr, &values[0]) ||
      !gumbo_attr_name_term(env, atoms, attr, &values[1]) ||
      !gumbo_attr_value_term(env, atoms, attr, &values[2]) ||
      !gumbo_attr_original_name_term(env, atoms, attr, &values[3]) ||
      !gumbo_attr_original_value_term(env, atoms, attr, &values[4]) ||
      !gumbo_attr_name_start_term(env, atoms, attr, &values[5]) ||
      !gumbo_attr_name_end_term(env, atoms, attr, &values[6]) ||
      !gumbo_attr_value_start_term(env, atoms, attr, &values[7]) ||
      !gumbo_attr_value_end_term(env, atoms, attr, &values[8])) {
    return 0;
  }

  return enif_make_map_from_arrays(env, keys, values, GUMBO_ATTR_DETAILS_COUNT,
                                   out);
}

ERL_NIF_TERM gumbo_nif_attr_details(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  GumboNode* node;
  if (gumbo_node_get(env, argv[0], argv[1], &h, &node) != GUMBO_NODE_OK) {
    return enif_make_tuple2(env, atoms->error, atoms->node.invalid_node);
  }
  (void)h; /* only the attribute is needed here */

  GumboAttribute* attr;
  if (!gumbo_attr_get(env, argv[2], node, &attr)) {
    return enif_make_tuple2(env, atoms->error,
                            atoms->attribute.invalid_attribute);
  }

  ERL_NIF_TERM map;
  if (!gumbo_attr_details_map(env, atoms, attr, &map)) {
    return enif_make_badarg(env);
  }
  return enif_make_tuple2(env, atoms->ok, map);
}
