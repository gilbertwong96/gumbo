#include "gumbo_node.h"

#include <stdio.h>
#include <string.h>

#include "gumbo.h"
#include "gumbo_atoms.h"
#include "gumbo_faults.h"
#include "gumbo_handle.h"

/* This file owns every scalar GumboNode field as one extractor each, plus
   the five node NIFs. The extractors are the single source of truth:
   node_details assembles the full map from them, and Task 8's materialize
   reuses them, so a field cannot be right in one place and wrong in
   another. Every term is built in the caller's environment per call; nothing
   created at load time is ever returned.

   Binding safety: gumbo's asserts are live (NDEBUG is not defined). The two
   reachable ones here — gumbo_normalized_tagname's range and
   gumbo_tag_from_original_text's four shape preconditions — are guarded the
   same way gumbo_tags.c guards them. */

/* ---- resolution and the error contract ---- */

/* A node index that is not in the handle's table is a programmer error, so
   the node-reference accessors raise ArgumentError with a message built in
   the caller's environment. The raise term is the exception struct itself:
   raising the {ArgumentError, message} tuple leaves an untranslated
   ErlangError, so build %ArgumentError{message: ...} by hand. */
static ERL_NIF_TERM gumbo_node_invalid(ErlNifEnv* env,
                                       const gumbo_atoms_t* atoms, int status,
                                       const ERL_NIF_TERM argv[]) {
  /* The casts acknowledge what cert-err33-c is right to notice: snprintf's
     return value is disregarded. Safe here, and it has to be said rather than
     assumed: 64 bytes holds every format below with room to spare — "invalid
     node index: %lu" is the longest, and an unsigned long prints in at most 20
     digits — so truncation cannot happen. The length that matters is built by
     strlen below, not by snprintf. */
  char message[64];
  if (status == GUMBO_NODE_INVALID_HANDLE) {
    (void)snprintf(message, sizeof(message), "invalid output handle");
  } else {
    unsigned long index;
    if (enif_get_ulong(env, argv[1], &index)) {
      (void)snprintf(message, sizeof(message), "invalid node index: %lu",
                     index);
    } else {
      /* A negative or bignum index has no ulong value, so report the
         failure without a bogus index of 0. */
      (void)snprintf(message, sizeof(message), "invalid node index");
    }
  }
  ERL_NIF_TERM message_term;
  /* strlen, not snprintf's return value: snprintf reports the length it
     would have written, unbounded by the 64-byte buffer, and using it as
     a length would read past the buffer on truncation. */
  if (!gumbo_make_binary(env, message, strlen(message), &message_term)) {
    return enif_make_badarg(env);
  }
  ERL_NIF_TERM keys[] = {atoms->node.struct_, atoms->node.exception_,
                         atoms->node.message};
  ERL_NIF_TERM values[] = {atoms->node.argument_error_module, atoms->true_,
                           message_term};
  ERL_NIF_TERM exception;
  if (!enif_make_map_from_arrays(env, keys, values, 3, &exception)) {
    return enif_make_badarg(env);
  }
  return enif_raise_exception(env, exception);
}

/* ---- node shape predicates ---- */

int gumbo_node_is_element(const GumboNode* node) {
  return node->type == GUMBO_NODE_ELEMENT || node->type == GUMBO_NODE_TEMPLATE;
}

static int gumbo_node_is_text_like(const GumboNode* node) {
  switch (node->type) {
    case GUMBO_NODE_TEXT:
    case GUMBO_NODE_CDATA:
    case GUMBO_NODE_COMMENT:
    case GUMBO_NODE_WHITESPACE:
    case GUMBO_NODE_PROCESSING_INSTRUCTION:
      return 1;
    default:
      return 0;
  }
}

/* ---- small term builders shared by several extractors ---- */

/* NUL-terminated string (doctype names, decoded text) or nil when NULL. */
int gumbo_node_stringz(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                       const char* s, ERL_NIF_TERM* out) {
  if (s == NULL) {
    *out = atoms->nil;
    return 1;
  }
  return gumbo_make_binary(env, s, strlen(s), out);
}

/* Length-delimited piece (original text, original tag). A zero-length piece
   is the empty binary; its data pointer is never touched in that case. */
int gumbo_node_string_piece(ErlNifEnv* env, GumboStringPiece piece,
                            ERL_NIF_TERM* out) {
  return gumbo_make_binary(env, piece.data, piece.length, out);
}

/* %Gumbo.Position{} built from a GumboSourcePosition. */
int gumbo_node_position_map(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                            GumboSourcePosition pos, ERL_NIF_TERM* out) {
  ERL_NIF_TERM keys[] = {atoms->node.struct_, atoms->node.line,
                         atoms->node.column, atoms->node.offset};
  ERL_NIF_TERM values[] = {
      atoms->node.position_module, enif_make_uint(env, pos.line),
      enif_make_uint(env, pos.column), enif_make_uint(env, pos.offset)};
  return enif_make_map_from_arrays(env, keys, values, 4, out);
}

/* ---- one scalar extractor per field ---- */

int gumbo_node_type_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                         const GumboNode* node, ERL_NIF_TERM* out) {
#ifdef GUMBO_TEST_FAULTS
  if (gumbo_fault_should_fail()) {
    /* A failure, on purpose: see gumbo_faults.h. */
    return GUMBO_FAULT_FAILURE(env, out);
  }
#endif

  (void)env;
  *out = atoms->node_types[node->type];
  return 1;
}

int gumbo_node_index_within_parent_term(ErlNifEnv* env,
                                        const gumbo_atoms_t* atoms,
                                        const GumboNode* node,
                                        ERL_NIF_TERM* out) {
  /* create_node sets parent to NULL and index_within_parent to (size_t)-1
     for never-appended nodes (the document node above all); without a
     parent there is no position, so nil — not SIZE_MAX as an integer. */
  if (node->parent == NULL) {
    *out = atoms->nil;
    return 1;
  }
  *out = enif_make_ulong(env, (unsigned long)node->index_within_parent);
  return 1;
}

int gumbo_node_parse_flags_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                const GumboNode* node, ERL_NIF_TERM* out) {
  /* parse_flags is a bitvector; GUMBO_INSERTION_NORMAL (0) is the empty
     list. Cons from the highest bit down so the list stays in declaration
     order. */
  ERL_NIF_TERM list = enif_make_list(env, 0);
  unsigned int bit;
  for (bit = (unsigned int)GUMBO_INSERTION_FOSTER_PARENTED; bit != 0;
       bit >>= 1u) {
    if (((unsigned int)node->parse_flags & bit) != 0) {
      list = enif_make_list_cell(env, atoms->parse_flags[bit], list);
    }
  }
  *out = list;
  return 1;
}

/* Start position. The document node's union member carries no position, so
   it reports kGumboEmptySourcePosition (all zeros), exactly as parser-
   inserted elements do. */
int gumbo_node_position_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                             const GumboNode* node, ERL_NIF_TERM* out) {
  GumboSourcePosition pos = kGumboEmptySourcePosition;
  if (gumbo_node_is_element(node)) {
    pos = node->v.element.start_pos;
  } else if (gumbo_node_is_text_like(node)) {
    pos = node->v.text.start_pos;
  }
  if (!gumbo_node_position_map(env, atoms, pos, out)) {
    return 0;
  }
  return 1;
}

int gumbo_node_has_doctype_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                const GumboNode* node, ERL_NIF_TERM* out) {
  (void)env;
  if (node->type != GUMBO_NODE_DOCUMENT) {
    *out = atoms->nil;
    return 1;
  }
  *out = node->v.document.has_doctype ? atoms->true_ : atoms->false_;
  return 1;
}

int gumbo_node_doctype_name_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                 const GumboNode* node, ERL_NIF_TERM* out) {
  if (node->type != GUMBO_NODE_DOCUMENT) {
    *out = atoms->nil;
    return 1;
  }
  return gumbo_node_stringz(env, atoms, node->v.document.name, out);
}

int gumbo_node_public_identifier_term(ErlNifEnv* env,
                                      const gumbo_atoms_t* atoms,
                                      const GumboNode* node,
                                      ERL_NIF_TERM* out) {
  if (node->type != GUMBO_NODE_DOCUMENT) {
    *out = atoms->nil;
    return 1;
  }
  return gumbo_node_stringz(env, atoms, node->v.document.public_identifier,
                            out);
}

int gumbo_node_system_identifier_term(ErlNifEnv* env,
                                      const gumbo_atoms_t* atoms,
                                      const GumboNode* node,
                                      ERL_NIF_TERM* out) {
  if (node->type != GUMBO_NODE_DOCUMENT) {
    *out = atoms->nil;
    return 1;
  }
  return gumbo_node_stringz(env, atoms, node->v.document.system_identifier,
                            out);
}

int gumbo_node_quirks_mode_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                const GumboNode* node, ERL_NIF_TERM* out) {
  (void)env;
  if (node->type != GUMBO_NODE_DOCUMENT) {
    *out = atoms->nil;
    return 1;
  }
  *out = atoms->quirks_modes[node->v.document.doc_type_quirks_mode];
  return 1;
}

int gumbo_node_tag_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                        const GumboNode* node, ERL_NIF_TERM* out) {
  (void)env;
  if (!gumbo_node_is_element(node)) {
    *out = atoms->nil;
    return 1;
  }
  *out = atoms->tags[node->v.element.tag];
  return 1;
}

int gumbo_node_tag_name_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                             const GumboNode* node, ERL_NIF_TERM* out) {
  if (!gumbo_node_is_element(node)) {
    *out = atoms->nil;
    return 1;
  }
  const GumboElement* element = &node->v.element;

  const char* name;
  size_t len;
  if (element->tag == GUMBO_TAG_UNKNOWN) {
    /* Resolve the real name from original_tag, which the parser stores as a
       complete tag including the trailing '>' for source-derived elements
       (<my-tag data-a=1>), and as a zero-length piece for parser-inserted
       ones. The guard mirrors gumbo_nif_tag_from_original_text: gumbo's four
       shape asserts are live, so a piece that does not provably satisfy
       them never reaches gumbo_tag_from_original_text, and a zero-length
       piece has no recoverable name. */
    const char* data = element->original_tag.data;
    size_t piece_len = element->original_tag.length;
    if (piece_len < 2 || data[0] != '<' || data[piece_len - 1] != '>' ||
        (data[1] == '/' && piece_len < 3)) {
      *out = atoms->nil;
      return 1;
    }
    GumboStringPiece piece = {data, piece_len};
    gumbo_tag_from_original_text(&piece);
    if (piece.length == 0) {
      *out = atoms->nil;
      return 1; /* "<>" or "</>": empty name, not a tag */
    }
    name = piece.data;
    len = piece.length;
  } else {
    /* Known tags come from gumbo's own static table; the tag value is
       parser-produced so gumbo_normalized_tagname's assert range is
       satisfied by construction. */
    name = gumbo_normalized_tagname(element->tag);
    len = strlen(name);
  }

  if (element->tag_namespace == GUMBO_NAMESPACE_SVG) {
    GumboStringPiece piece = {name, len};
    const char* svg_name = gumbo_normalize_svg_tagname(&piece);
    if (svg_name != NULL) {
      name = svg_name;
      len = strlen(svg_name);
    }
  }

  if (!gumbo_make_binary(env, name, len, out)) {
    return 0;
  }
  return 1;
}

int gumbo_node_namespace_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                              const GumboNode* node, ERL_NIF_TERM* out) {
  (void)env;
  if (!gumbo_node_is_element(node)) {
    *out = atoms->nil;
    return 1;
  }
  *out = atoms->namespaces[node->v.element.tag_namespace];
  return 1;
}

int gumbo_node_original_tag_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                 const GumboNode* node, ERL_NIF_TERM* out) {
  if (!gumbo_node_is_element(node)) {
    *out = atoms->nil;
    return 1;
  }
  return gumbo_node_string_piece(env, node->v.element.original_tag, out);
}

int gumbo_node_original_end_tag_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     const GumboNode* node, ERL_NIF_TERM* out) {
  if (!gumbo_node_is_element(node)) {
    *out = atoms->nil;
    return 1;
  }
  return gumbo_node_string_piece(env, node->v.element.original_end_tag, out);
}

int gumbo_node_end_position_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                 const GumboNode* node, ERL_NIF_TERM* out) {
  if (!gumbo_node_is_element(node)) {
    *out = atoms->nil;
    return 1;
  }
  if (!gumbo_node_position_map(env, atoms, node->v.element.end_pos, out)) {
    return 0;
  }
  return 1;
}

int gumbo_node_text_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                         const GumboNode* node, ERL_NIF_TERM* out) {
  if (!gumbo_node_is_text_like(node)) {
    *out = atoms->nil;
    return 1;
  }
  return gumbo_node_stringz(env, atoms, node->v.text.text, out);
}

int gumbo_node_original_text_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                  const GumboNode* node, ERL_NIF_TERM* out) {
#ifdef GUMBO_TEST_FAULTS
  if (gumbo_fault_should_fail()) {
    /* A failure, on purpose: see gumbo_faults.h. */
    return GUMBO_FAULT_FAILURE(env, out);
  }
#endif

  if (!gumbo_node_is_text_like(node)) {
    *out = atoms->nil;
    return 1;
  }
  return gumbo_node_string_piece(env, node->v.text.original_text, out);
}

/* ---- the NIF entry points ---- */

#define GUMBO_NODE_DETAILS_COUNT 17

ERL_NIF_TERM gumbo_nif_node_details(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  GumboNode* node;
  if (gumbo_node_get(env, argv[0], argv[1], &h, &node) != GUMBO_NODE_OK) {
    return enif_make_tuple2(env, atoms->error, atoms->node.invalid_node);
  }
  (void)h; /* only the node is needed here */

  ERL_NIF_TERM keys[GUMBO_NODE_DETAILS_COUNT] = {
      atoms->node.type,
      atoms->node.index_within_parent,
      atoms->node.parse_flags,
      atoms->node.position,
      atoms->node.has_doctype,
      atoms->node.doctype_name,
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
  };
  ERL_NIF_TERM values[GUMBO_NODE_DETAILS_COUNT];

  /* Each extraction is asked whether it succeeded. This is the array the defect
     lived in: a failure used to travel into it and be read back as a term that
     was never a value. */
  if (!gumbo_node_type_term(env, atoms, node, &values[0]) ||
      !gumbo_node_index_within_parent_term(env, atoms, node, &values[1]) ||
      !gumbo_node_parse_flags_term(env, atoms, node, &values[2]) ||
      !gumbo_node_position_term(env, atoms, node, &values[3]) ||
      !gumbo_node_has_doctype_term(env, atoms, node, &values[4]) ||
      !gumbo_node_doctype_name_term(env, atoms, node, &values[5]) ||
      !gumbo_node_public_identifier_term(env, atoms, node, &values[6]) ||
      !gumbo_node_system_identifier_term(env, atoms, node, &values[7]) ||
      !gumbo_node_quirks_mode_term(env, atoms, node, &values[8]) ||
      !gumbo_node_tag_term(env, atoms, node, &values[9]) ||
      !gumbo_node_tag_name_term(env, atoms, node, &values[10]) ||
      !gumbo_node_namespace_term(env, atoms, node, &values[11]) ||
      !gumbo_node_original_tag_term(env, atoms, node, &values[12]) ||
      !gumbo_node_original_end_tag_term(env, atoms, node, &values[13]) ||
      !gumbo_node_end_position_term(env, atoms, node, &values[14]) ||
      !gumbo_node_text_term(env, atoms, node, &values[15]) ||
      !gumbo_node_original_text_term(env, atoms, node, &values[16])) {
    return enif_make_badarg(env);
  }
  ERL_NIF_TERM map;
  if (!enif_make_map_from_arrays(env, keys, values, GUMBO_NODE_DETAILS_COUNT,
                                 &map)) {
    return enif_make_badarg(env);
  }
  return enif_make_tuple2(env, atoms->ok, map);
}

ERL_NIF_TERM gumbo_nif_node_children(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  GumboNode* node;
  int status = gumbo_node_get(env, argv[0], argv[1], &h, &node);
  if (status != GUMBO_NODE_OK) {
    return gumbo_node_invalid(env, atoms, status, argv);
  }

  unsigned long index;
  if (!enif_get_ulong(env, argv[1], &index)) {
    return enif_make_badarg(env);
  }

  ERL_NIF_TERM list = enif_make_list(env, 0);
  GumboVector* children = gumbo_node_children(node);
  if (children != NULL && children->length > 0) {
    unsigned long* indices =
        enif_alloc((size_t)children->length * sizeof(unsigned long));
    if (indices == NULL) {
      return enif_make_badarg(env);
    }
    /* Children are contiguous subtree ranges in preorder: child 0 starts at
       index + 1 and each later child starts right after the previous one's
       subtree. Collect the indices forward, then cons from the end so the
       list comes out in source order. */
    size_t next = (size_t)index + 1;
    unsigned int i;
    for (i = 0; i < children->length; ++i) {
      indices[i] = (unsigned long)next;
      next += h->subtree_sizes[next];
    }
    for (i = children->length; i-- > 0;) {
      list = enif_make_list_cell(env, enif_make_ulong(env, indices[i]), list);
    }
    enif_free(indices);
  }
  return list;
}

ERL_NIF_TERM gumbo_nif_node_parent(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                   int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  GumboNode* node;
  int status = gumbo_node_get(env, argv[0], argv[1], &h, &node);
  if (status != GUMBO_NODE_OK) {
    return gumbo_node_invalid(env, atoms, status, argv);
  }

  unsigned long index;
  if (!enif_get_ulong(env, argv[1], &index)) {
    return enif_make_badarg(env);
  }

  size_t parent = h->parent_indices[index];
  if (parent == GUMBO_NO_PARENT) {
    return atoms->nil; /* the document node has no parent */
  }
  return enif_make_ulong(env, (unsigned long)parent);
}

ERL_NIF_TERM gumbo_nif_node_next(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                 int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  GumboNode* node;
  int status = gumbo_node_get(env, argv[0], argv[1], &h, &node);
  if (status != GUMBO_NODE_OK) {
    return gumbo_node_invalid(env, atoms, status, argv);
  }

  /* Gumbo stores no sibling pointers: the next sibling is the node right
     after this node's subtree, if the parent's children vector has one. */
  if (node->parent == NULL) {
    return atoms->nil;
  }
  GumboVector* siblings = gumbo_node_children(node->parent);
  if (node->index_within_parent + 1 >= siblings->length) {
    return atoms->nil;
  }

  unsigned long index;
  if (!enif_get_ulong(env, argv[1], &index)) {
    return enif_make_badarg(env);
  }
  return enif_make_ulong(
      env, (unsigned long)((size_t)index + h->subtree_sizes[index]));
}

ERL_NIF_TERM gumbo_nif_node_previous(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  GumboNode* node;
  int status = gumbo_node_get(env, argv[0], argv[1], &h, &node);
  if (status != GUMBO_NODE_OK) {
    return gumbo_node_invalid(env, atoms, status, argv);
  }

  if (node->parent == NULL || node->index_within_parent == 0) {
    return atoms->nil;
  }

  unsigned long index;
  if (!enif_get_ulong(env, argv[1], &index)) {
    return enif_make_badarg(env);
  }

  /* The preceding sibling: start at the parent's first child and skip each
     earlier child's subtree in turn. */
  size_t prev = h->parent_indices[index] + 1;
  size_t i;
  for (i = 0; i + 1 < node->index_within_parent; ++i) {
    prev += h->subtree_sizes[prev];
  }
  return enif_make_ulong(env, (unsigned long)prev);
}

ERL_NIF_TERM gumbo_nif_node_attributes(ErlNifEnv* env,
                                       const gumbo_atoms_t* atoms, int argc,
                                       const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  GumboNode* node;
  int status = gumbo_node_get(env, argv[0], argv[1], &h, &node);
  if (status != GUMBO_NODE_OK) {
    return gumbo_node_invalid(env, atoms, status, argv);
  }
  (void)h;

  ERL_NIF_TERM list = enif_make_list(env, 0);
  if (gumbo_node_is_element(node)) {
    GumboVector* attributes = &node->v.element.attributes;
    /* Cons from the end so the list stays in source order. */
    unsigned int i;
    for (i = attributes->length; i-- > 0;) {
      list = enif_make_list_cell(env, enif_make_ulong(env, i), list);
    }
  }
  return list;
}

/* gumbo_get_attribute compares with strcasecmp in a loop, which needs a
   NUL-terminated C string; an Elixir binary is not one. The name is copied
   into a terminated buffer (stack below 256 bytes, heap above), and a name
   containing a NUL byte yields nil: passing one through would silently
   truncate the search and could match the wrong attribute. attribute.c has
   no asserts, so the call itself needs no other guard. */
#define GUMBO_NODE_ATTR_NAME_STACK 256

ERL_NIF_TERM gumbo_nif_node_attribute(ErlNifEnv* env,
                                      const gumbo_atoms_t* atoms, int argc,
                                      const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  GumboNode* node;
  int status = gumbo_node_get(env, argv[0], argv[1], &h, &node);
  if (status != GUMBO_NODE_OK) {
    return gumbo_node_invalid(env, atoms, status, argv);
  }
  (void)h;

  /* The argument check comes before the element check so an invalid name
     behaves the same on every node type: nil documents "off elements",
     not a different failure mode for the same bad argument. */
  ErlNifBinary name;
  if (!enif_inspect_binary(env, argv[2], &name)) {
    return enif_make_badarg(env);
  }

  if (!gumbo_node_is_element(node)) {
    return atoms->nil;
  }

  if (memchr(name.data, '\0', name.size) != NULL) {
    return atoms->nil;
  }

  char stack_buf[GUMBO_NODE_ATTR_NAME_STACK];
  char* buf = stack_buf;
  if (name.size >= sizeof(stack_buf)) {
    buf = enif_alloc(name.size + 1);
    if (buf == NULL) {
      return enif_make_badarg(env);
    }
  }
  memcpy(buf, name.data, name.size);
  buf[name.size] = '\0';

  GumboAttribute* attr = gumbo_get_attribute(&node->v.element.attributes, buf);
  if (buf != stack_buf) {
    enif_free(buf);
  }
  if (attr == NULL) {
    return atoms->nil;
  }

  /* The matched attribute's index in the vector, by pointer comparison
     rather than arithmetic on the void** data. */
  GumboVector* attributes = &node->v.element.attributes;
  unsigned int i;
  for (i = 0; i < attributes->length; ++i) {
    if (attributes->data[i] == attr) {
      return enif_make_ulong(env, i);
    }
  }
  /* Unreachable: gumbo_get_attribute only returns vector members. */
  return atoms->nil;
}
