#ifndef GUMBO_ATOMS_H_
#define GUMBO_ATOMS_H_

#include <erl_nif.h>
#include <stddef.h>
#include <string.h>

#include "error.h"
#include "gumbo.h"
#include "insertion_mode.h"
#include "token_type.h"

/* Enum family sizes, derived as LAST_MEMBER + 1 with the literal written in a
   comment: none of these enums has a _LAST sentinel, so a gumbo bump that
   adds a member shows up as a visible change here. */
#define GUMBO_NODE_TYPE_COUNT (GUMBO_NODE_PROCESSING_INSTRUCTION + 1) /* 8 */
#define GUMBO_NAMESPACE_COUNT (GUMBO_NAMESPACE_MATHML + 1)            /* 3 */
#define GUMBO_ATTR_NAMESPACE_COUNT (GUMBO_ATTR_NAMESPACE_XMLNS + 1)   /* 4 */
#define GUMBO_QUIRKS_MODE_COUNT (GUMBO_DOCTYPE_LIMITED_QUIRKS + 1)    /* 3 */
/* 11, deliberately not GUMBO_INSERTION_FOSTER_PARENTED + 1: the 1 << 2 flag
   was removed upstream and leaves a hole in the bit values. */
#define GUMBO_PARSE_FLAG_COUNT 11
#define GUMBO_ERROR_TYPE_COUNT \
  (GUMBO_ERR_NONCHARACTER_IN_INPUT_STREAM + 1)                      /* 44 */
#define GUMBO_TOKENIZER_STATE_COUNT (GUMBO_ERR_TOKENIZER_CDATA + 1) /* 14 */
#define GUMBO_TOKEN_TYPE_COUNT                   \
  (GUMBO_TOKEN_PROCESSING_INSTRUCTION + 1) /* 10 \
                                            */
#define GUMBO_INSERTION_MODE_COUNT \
  (GUMBO_INSERTION_MODE_AFTER_AFTER_FRAMESET + 1) /* 21 */

/* Tags: GUMBO_TAG_LAST is 154 real names + GUMBO_TAG_UNKNOWN + the LAST
   marker, so the tag table itself holds 155 entries. The names are NOT
   cached as binaries here: a binary term created in the load callback's
   environment is not valid in later NIF calls, so gumbo_nif_tag_name builds
   them per call. */
#define GUMBO_TAG_COUNT (GUMBO_TAG_LAST) /* 155 */

/* Parse flags are single bits (0 and 1 << 0 .. 1 << 10); the table is sparse
   and indexed by the raw flag value so a consumer can look a bit up
   directly. */
#define GUMBO_PARSE_FLAG_TABLE_SIZE \
  (GUMBO_INSERTION_FOSTER_PARENTED + 1) /* 1025 */

/* All atom tables, interned once in gumbo_atoms_init from gumbo_nif_load.
   Every enum family follows one mechanical rule (strip the family prefix,
   lowercase ASCII, keep underscores); tags are the one exception (see
   gumbo_atoms.c). Consumers must reuse these terms and never call
   enif_make_atom at request time. */
typedef struct {
  ERL_NIF_TERM node_types[GUMBO_NODE_TYPE_COUNT];
  ERL_NIF_TERM namespaces[GUMBO_NAMESPACE_COUNT];
  ERL_NIF_TERM attribute_namespaces[GUMBO_ATTR_NAMESPACE_COUNT];
  ERL_NIF_TERM quirks_modes[GUMBO_QUIRKS_MODE_COUNT];
  ERL_NIF_TERM parse_flags[GUMBO_PARSE_FLAG_TABLE_SIZE];
  ERL_NIF_TERM error_types[GUMBO_ERROR_TYPE_COUNT];
  ERL_NIF_TERM tokenizer_states[GUMBO_TOKENIZER_STATE_COUNT];
  ERL_NIF_TERM token_types[GUMBO_TOKEN_TYPE_COUNT];
  ERL_NIF_TERM insertion_modes[GUMBO_INSERTION_MODE_COUNT];

  ERL_NIF_TERM tags[GUMBO_TAG_COUNT]; /* tag atom per value */

  ERL_NIF_TERM ok;
  ERL_NIF_TERM error;
  ERL_NIF_TERM true_;
  ERL_NIF_TERM false_;
  ERL_NIF_TERM nil;
  ERL_NIF_TERM not_a_tag;

  /* Parse and option atoms: the to_nif/1 map keys, the :dirty values that are
     not already true_/false_/nil, and the handle/option error reasons. */
  ERL_NIF_TERM tab_stop;
  ERL_NIF_TERM stop_on_first_error;
  ERL_NIF_TERM max_errors;
  ERL_NIF_TERM max_attributes;
  ERL_NIF_TERM max_tree_depth;
  ERL_NIF_TERM fragment_context;
  ERL_NIF_TERM fragment_namespace;
  ERL_NIF_TERM dirty;
  ERL_NIF_TERM auto_;
  ERL_NIF_TERM invalid_handle;
  ERL_NIF_TERM invalid_option;
  ERL_NIF_TERM input_too_large;
  ERL_NIF_TERM too_many_attributes;
  ERL_NIF_TERM too_deep;
  ERL_NIF_TERM tree_too_deep;

  /* Node accessor atoms, grouped so the details-map key :parse_flags and the
     enum table parse_flags[] cannot be confused. Includes the
     %Gumbo.Position{} struct keys (struct_ + the position module atom), the
     error atoms the node NIFs return or raise, and materialize's key
     renames of the details-map keys (:position -> :start_position,
     :doctype_name -> :name) plus the :attributes/:children keys only the
     materialized maps carry. */
  struct {
    ERL_NIF_TERM type;
    ERL_NIF_TERM index_within_parent;
    ERL_NIF_TERM parse_flags;
    ERL_NIF_TERM position;
    ERL_NIF_TERM has_doctype;
    ERL_NIF_TERM doctype_name;
    ERL_NIF_TERM public_identifier;
    ERL_NIF_TERM system_identifier;
    ERL_NIF_TERM quirks_mode;
    ERL_NIF_TERM tag;
    ERL_NIF_TERM tag_name;
    ERL_NIF_TERM namespace;
    ERL_NIF_TERM original_tag;
    ERL_NIF_TERM original_end_tag;
    ERL_NIF_TERM end_position;
    ERL_NIF_TERM text;
    ERL_NIF_TERM original_text;
    /* The processing instruction's two halves, which gumbo keeps in one
       string: see gumbo_node_pi_halves. */
    ERL_NIF_TERM target;
    ERL_NIF_TERM data;
    ERL_NIF_TERM start_position;
    ERL_NIF_TERM name;
    ERL_NIF_TERM attributes;
    ERL_NIF_TERM children;
    ERL_NIF_TERM struct_;
    ERL_NIF_TERM position_module;
    ERL_NIF_TERM line;
    ERL_NIF_TERM column;
    ERL_NIF_TERM offset;
    ERL_NIF_TERM argument_error_module;
    ERL_NIF_TERM exception_;
    ERL_NIF_TERM message;
    ERL_NIF_TERM invalid_node;
  } node;

  /* Materialize result atoms: materialize_output's result-map keys. */
  struct {
    ERL_NIF_TERM document;
    ERL_NIF_TERM root;
    ERL_NIF_TERM errors;
  } materialize;

  /* Attribute accessor atoms: the attr_details-map keys named after the
     accessors they feed, plus the error atom a bad attribute index
     yields. */
  struct {
    ERL_NIF_TERM namespace;
    ERL_NIF_TERM name;
    ERL_NIF_TERM value;
    ERL_NIF_TERM original_name;
    ERL_NIF_TERM original_value;
    ERL_NIF_TERM name_start;
    ERL_NIF_TERM name_end;
    ERL_NIF_TERM value_start;
    ERL_NIF_TERM value_end;
    ERL_NIF_TERM invalid_attribute;
  } attribute;

  /* Error accessor atoms: the error_details-map keys named after the
     accessors they feed, plus the keys of the type-specific submaps
     (tokenizer, duplicate_attr, parser_error). The :invalid_node reason a
     bad error index yields is atoms->node.invalid_node, exactly as
     attr_details reuses it. */
  struct {
    ERL_NIF_TERM type;
    ERL_NIF_TERM position;
    ERL_NIF_TERM original_text;
    ERL_NIF_TERM message;
    ERL_NIF_TERM caret;
    ERL_NIF_TERM codepoint;
    ERL_NIF_TERM tokenizer;
    ERL_NIF_TERM text;
    ERL_NIF_TERM duplicate_attr;
    ERL_NIF_TERM parser_error;
    ERL_NIF_TERM state;
    ERL_NIF_TERM name;
    ERL_NIF_TERM original_index;
    ERL_NIF_TERM new_index;
    ERL_NIF_TERM input_type;
    ERL_NIF_TERM input_tag;
    ERL_NIF_TERM insertion_mode;
    ERL_NIF_TERM tag_stack;
  } error_;
} gumbo_atoms_t;

/* Interns every table above. Returns 0 on success; a nonzero return makes
   the NIF load fail. */
int gumbo_atoms_init(ErlNifEnv* env, gumbo_atoms_t* atoms);

/* Builds a binary term from a length-delimited buffer. enif_make_string and
   enif_make_string_len are deliberately not used: on the OTP we build
   against they return a list of integers, not a binary. Returns 1 on
   success; on allocation failure returns 0 and leaves *out untouched. */
static inline int gumbo_make_binary(ErlNifEnv* env, const char* data,
                                    size_t len, ERL_NIF_TERM* out) {
  ErlNifBinary bin;
  if (!enif_alloc_binary(len, &bin)) {
    return 0;
  }
  if (len > 0) {
    memcpy(bin.data, data, len);
  }
  *out = enif_make_binary(env, &bin);
  return 1;
}

#endif /* GUMBO_ATOMS_H_ */
