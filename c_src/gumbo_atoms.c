#include "gumbo_atoms.h"

#include <string.h>

/* The X-macro member lists below are the only transcribed data in this file:
   each enum's members in declaration order. The atom names are then derived
   mechanically — strip the family prefix, lowercase ASCII, keep underscores
   — so there is no hand-written enum-to-atom table that can drift. The
   compile-time size checks fail if a list and its enum get out of step, and
   the prefix check in gumbo_atom_name catches a member copied from the wrong
   family. */

#define GUMBO_NODE_TYPES(X) \
  X(GUMBO_NODE_DOCUMENT)    \
  X(GUMBO_NODE_ELEMENT)     \
  X(GUMBO_NODE_TEXT)        \
  X(GUMBO_NODE_CDATA)       \
  X(GUMBO_NODE_COMMENT)     \
  X(GUMBO_NODE_WHITESPACE)  \
  X(GUMBO_NODE_TEMPLATE)    \
  X(GUMBO_NODE_PROCESSING_INSTRUCTION)

#define GUMBO_NAMESPACES(X) \
  X(GUMBO_NAMESPACE_HTML)   \
  X(GUMBO_NAMESPACE_SVG)    \
  X(GUMBO_NAMESPACE_MATHML)

#define GUMBO_ATTR_NAMESPACES(X) \
  X(GUMBO_ATTR_NAMESPACE_NONE)   \
  X(GUMBO_ATTR_NAMESPACE_XLINK)  \
  X(GUMBO_ATTR_NAMESPACE_XML)    \
  X(GUMBO_ATTR_NAMESPACE_XMLNS)

#define GUMBO_QUIRKS_MODES(X) \
  X(GUMBO_DOCTYPE_NO_QUIRKS)  \
  X(GUMBO_DOCTYPE_QUIRKS)     \
  X(GUMBO_DOCTYPE_LIMITED_QUIRKS)

#define GUMBO_PARSE_FLAGS(X)                          \
  X(GUMBO_INSERTION_NORMAL)                           \
  X(GUMBO_INSERTION_BY_PARSER)                        \
  X(GUMBO_INSERTION_IMPLICIT_END_TAG)                 \
  X(GUMBO_INSERTION_IMPLIED)                          \
  X(GUMBO_INSERTION_CONVERTED_FROM_END_TAG)           \
  X(GUMBO_INSERTION_FROM_ISINDEX)                     \
  X(GUMBO_INSERTION_FROM_IMAGE)                       \
  X(GUMBO_INSERTION_RECONSTRUCTED_FORMATTING_ELEMENT) \
  X(GUMBO_INSERTION_ADOPTION_AGENCY_CLONED)           \
  X(GUMBO_INSERTION_ADOPTION_AGENCY_MOVED)            \
  X(GUMBO_INSERTION_FOSTER_PARENTED)

#define GUMBO_ERROR_TYPES(X)                      \
  X(GUMBO_ERR_UTF8_INVALID)                       \
  X(GUMBO_ERR_UTF8_TRUNCATED)                     \
  X(GUMBO_ERR_UTF8_NULL)                          \
  X(GUMBO_ERR_NUMERIC_CHAR_REF_NO_DIGITS)         \
  X(GUMBO_ERR_NUMERIC_CHAR_REF_WITHOUT_SEMICOLON) \
  X(GUMBO_ERR_NUMERIC_CHAR_REF_INVALID)           \
  X(GUMBO_ERR_NAMED_CHAR_REF_WITHOUT_SEMICOLON)   \
  X(GUMBO_ERR_NAMED_CHAR_REF_INVALID)             \
  X(GUMBO_ERR_TAG_STARTS_WITH_QUESTION)           \
  X(GUMBO_ERR_TAG_EOF)                            \
  X(GUMBO_ERR_TAG_INVALID)                        \
  X(GUMBO_ERR_CLOSE_TAG_EMPTY)                    \
  X(GUMBO_ERR_CLOSE_TAG_EOF)                      \
  X(GUMBO_ERR_CLOSE_TAG_INVALID)                  \
  X(GUMBO_ERR_SCRIPT_EOF)                         \
  X(GUMBO_ERR_ATTR_NAME_EOF)                      \
  X(GUMBO_ERR_ATTR_NAME_INVALID)                  \
  X(GUMBO_ERR_ATTR_DOUBLE_QUOTE_EOF)              \
  X(GUMBO_ERR_ATTR_SINGLE_QUOTE_EOF)              \
  X(GUMBO_ERR_ATTR_UNQUOTED_EOF)                  \
  X(GUMBO_ERR_ATTR_UNQUOTED_RIGHT_BRACKET)        \
  X(GUMBO_ERR_ATTR_UNQUOTED_EQUALS)               \
  X(GUMBO_ERR_ATTR_AFTER_EOF)                     \
  X(GUMBO_ERR_ATTR_AFTER_INVALID)                 \
  X(GUMBO_ERR_DUPLICATE_ATTR)                     \
  X(GUMBO_ERR_SOLIDUS_EOF)                        \
  X(GUMBO_ERR_SOLIDUS_INVALID)                    \
  X(GUMBO_ERR_DASHES_OR_DOCTYPE)                  \
  X(GUMBO_ERR_COMMENT_EOF)                        \
  X(GUMBO_ERR_COMMENT_INVALID)                    \
  X(GUMBO_ERR_COMMENT_BANG_AFTER_DOUBLE_DASH)     \
  X(GUMBO_ERR_COMMENT_DASH_AFTER_DOUBLE_DASH)     \
  X(GUMBO_ERR_COMMENT_SPACE_AFTER_DOUBLE_DASH)    \
  X(GUMBO_ERR_COMMENT_END_BANG_EOF)               \
  X(GUMBO_ERR_DOCTYPE_EOF)                        \
  X(GUMBO_ERR_DOCTYPE_INVALID)                    \
  X(GUMBO_ERR_DOCTYPE_SPACE)                      \
  X(GUMBO_ERR_DOCTYPE_RIGHT_BRACKET)              \
  X(GUMBO_ERR_DOCTYPE_SPACE_OR_RIGHT_BRACKET)     \
  X(GUMBO_ERR_DOCTYPE_END)                        \
  X(GUMBO_ERR_PARSER)                             \
  X(GUMBO_ERR_UNACKNOWLEDGED_SELF_CLOSING_TAG)    \
  X(GUMBO_ERR_CONTROL_CHARACTER_IN_INPUT_STREAM)  \
  X(GUMBO_ERR_NONCHARACTER_IN_INPUT_STREAM)

#define GUMBO_TOKENIZER_STATES(X)           \
  X(GUMBO_ERR_TOKENIZER_DATA)               \
  X(GUMBO_ERR_TOKENIZER_CHAR_REF)           \
  X(GUMBO_ERR_TOKENIZER_RCDATA)             \
  X(GUMBO_ERR_TOKENIZER_RAWTEXT)            \
  X(GUMBO_ERR_TOKENIZER_PLAINTEXT)          \
  X(GUMBO_ERR_TOKENIZER_SCRIPT)             \
  X(GUMBO_ERR_TOKENIZER_TAG)                \
  X(GUMBO_ERR_TOKENIZER_SELF_CLOSING_TAG)   \
  X(GUMBO_ERR_TOKENIZER_ATTR_NAME)          \
  X(GUMBO_ERR_TOKENIZER_ATTR_VALUE)         \
  X(GUMBO_ERR_TOKENIZER_MARKUP_DECLARATION) \
  X(GUMBO_ERR_TOKENIZER_COMMENT)            \
  X(GUMBO_ERR_TOKENIZER_DOCTYPE)            \
  X(GUMBO_ERR_TOKENIZER_CDATA)

#define GUMBO_TOKEN_TYPES(X) \
  X(GUMBO_TOKEN_DOCTYPE)     \
  X(GUMBO_TOKEN_START_TAG)   \
  X(GUMBO_TOKEN_END_TAG)     \
  X(GUMBO_TOKEN_COMMENT)     \
  X(GUMBO_TOKEN_WHITESPACE)  \
  X(GUMBO_TOKEN_CHARACTER)   \
  X(GUMBO_TOKEN_CDATA)       \
  X(GUMBO_TOKEN_NULL)        \
  X(GUMBO_TOKEN_EOF)         \
  X(GUMBO_TOKEN_PROCESSING_INSTRUCTION)

#define GUMBO_INSERTION_MODES(X)             \
  X(GUMBO_INSERTION_MODE_INITIAL)            \
  X(GUMBO_INSERTION_MODE_BEFORE_HTML)        \
  X(GUMBO_INSERTION_MODE_BEFORE_HEAD)        \
  X(GUMBO_INSERTION_MODE_IN_HEAD)            \
  X(GUMBO_INSERTION_MODE_IN_HEAD_NOSCRIPT)   \
  X(GUMBO_INSERTION_MODE_AFTER_HEAD)         \
  X(GUMBO_INSERTION_MODE_IN_BODY)            \
  X(GUMBO_INSERTION_MODE_TEXT)               \
  X(GUMBO_INSERTION_MODE_IN_TABLE)           \
  X(GUMBO_INSERTION_MODE_IN_TABLE_TEXT)      \
  X(GUMBO_INSERTION_MODE_IN_CAPTION)         \
  X(GUMBO_INSERTION_MODE_IN_COLUMN_GROUP)    \
  X(GUMBO_INSERTION_MODE_IN_TABLE_BODY)      \
  X(GUMBO_INSERTION_MODE_IN_ROW)             \
  X(GUMBO_INSERTION_MODE_IN_CELL)            \
  X(GUMBO_INSERTION_MODE_IN_SELECT)          \
  X(GUMBO_INSERTION_MODE_IN_SELECT_IN_TABLE) \
  X(GUMBO_INSERTION_MODE_IN_TEMPLATE)        \
  X(GUMBO_INSERTION_MODE_AFTER_BODY)         \
  X(GUMBO_INSERTION_MODE_IN_FRAMESET)        \
  X(GUMBO_INSERTION_MODE_AFTER_FRAMESET)     \
  X(GUMBO_INSERTION_MODE_AFTER_AFTER_BODY)   \
  X(GUMBO_INSERTION_MODE_AFTER_AFTER_FRAMESET)

#define GUMBO_X_STR(member) #member,
#define GUMBO_X_VALUE(member) member,

static const int kGumboNodeTypeValues[] = {GUMBO_NODE_TYPES(GUMBO_X_VALUE)};
static const char* const kGumboNodeTypeNames[] = {
    GUMBO_NODE_TYPES(GUMBO_X_STR)};
static const int kGumboNamespaceValues[] = {GUMBO_NAMESPACES(GUMBO_X_VALUE)};
static const char* const kGumboNamespaceNames[] = {
    GUMBO_NAMESPACES(GUMBO_X_STR)};
static const int kGumboAttrNamespaceValues[] = {
    GUMBO_ATTR_NAMESPACES(GUMBO_X_VALUE)};
static const char* const kGumboAttrNamespaceNames[] = {
    GUMBO_ATTR_NAMESPACES(GUMBO_X_STR)};
static const int kGumboQuirksModeValues[] = {GUMBO_QUIRKS_MODES(GUMBO_X_VALUE)};
static const char* const kGumboQuirksModeNames[] = {
    GUMBO_QUIRKS_MODES(GUMBO_X_STR)};
static const int kGumboParseFlagValues[] = {GUMBO_PARSE_FLAGS(GUMBO_X_VALUE)};
static const char* const kGumboParseFlagNames[] = {
    GUMBO_PARSE_FLAGS(GUMBO_X_STR)};
static const int kGumboErrorTypeValues[] = {GUMBO_ERROR_TYPES(GUMBO_X_VALUE)};
static const char* const kGumboErrorTypeNames[] = {
    GUMBO_ERROR_TYPES(GUMBO_X_STR)};
static const int kGumboTokenizerStateValues[] = {
    GUMBO_TOKENIZER_STATES(GUMBO_X_VALUE)};
static const char* const kGumboTokenizerStateNames[] = {
    GUMBO_TOKENIZER_STATES(GUMBO_X_STR)};
static const int kGumboTokenTypeValues[] = {GUMBO_TOKEN_TYPES(GUMBO_X_VALUE)};
static const char* const kGumboTokenTypeNames[] = {
    GUMBO_TOKEN_TYPES(GUMBO_X_STR)};
static const int kGumboInsertionModeValues[] = {
    GUMBO_INSERTION_MODES(GUMBO_X_VALUE)};
static const char* const kGumboInsertionModeNames[] = {
    GUMBO_INSERTION_MODES(GUMBO_X_STR)};

/* Compile-time checks that each member list has exactly the count derived
   from its enum. A list that is too short would otherwise silently leave
   zeros (invalid terms) in the table, and one that is too long would
   overflow nothing but still indicate drift. */
typedef char gumbo_node_type_list_check
    [(sizeof(kGumboNodeTypeValues) / sizeof(kGumboNodeTypeValues[0]) ==
          GUMBO_NODE_TYPE_COUNT &&
      sizeof(kGumboNodeTypeNames) / sizeof(kGumboNodeTypeNames[0]) ==
          GUMBO_NODE_TYPE_COUNT)
         ? 1
         : -1];
typedef char gumbo_namespace_list_check
    [(sizeof(kGumboNamespaceValues) / sizeof(kGumboNamespaceValues[0]) ==
          GUMBO_NAMESPACE_COUNT &&
      sizeof(kGumboNamespaceNames) / sizeof(kGumboNamespaceNames[0]) ==
          GUMBO_NAMESPACE_COUNT)
         ? 1
         : -1];
typedef char gumbo_attr_namespace_list_check
    [(sizeof(kGumboAttrNamespaceValues) /
              sizeof(kGumboAttrNamespaceValues[0]) ==
          GUMBO_ATTR_NAMESPACE_COUNT &&
      sizeof(kGumboAttrNamespaceNames) / sizeof(kGumboAttrNamespaceNames[0]) ==
          GUMBO_ATTR_NAMESPACE_COUNT)
         ? 1
         : -1];
typedef char gumbo_quirks_mode_list_check
    [(sizeof(kGumboQuirksModeValues) / sizeof(kGumboQuirksModeValues[0]) ==
          GUMBO_QUIRKS_MODE_COUNT &&
      sizeof(kGumboQuirksModeNames) / sizeof(kGumboQuirksModeNames[0]) ==
          GUMBO_QUIRKS_MODE_COUNT)
         ? 1
         : -1];
typedef char gumbo_parse_flag_list_check
    [(sizeof(kGumboParseFlagValues) / sizeof(kGumboParseFlagValues[0]) ==
          GUMBO_PARSE_FLAG_COUNT &&
      sizeof(kGumboParseFlagNames) / sizeof(kGumboParseFlagNames[0]) ==
          GUMBO_PARSE_FLAG_COUNT)
         ? 1
         : -1];
typedef char gumbo_error_type_list_check
    [(sizeof(kGumboErrorTypeValues) / sizeof(kGumboErrorTypeValues[0]) ==
          GUMBO_ERROR_TYPE_COUNT &&
      sizeof(kGumboErrorTypeNames) / sizeof(kGumboErrorTypeNames[0]) ==
          GUMBO_ERROR_TYPE_COUNT)
         ? 1
         : -1];
typedef char gumbo_tokenizer_state_list_check
    [(sizeof(kGumboTokenizerStateValues) /
              sizeof(kGumboTokenizerStateValues[0]) ==
          GUMBO_TOKENIZER_STATE_COUNT &&
      sizeof(kGumboTokenizerStateNames) /
              sizeof(kGumboTokenizerStateNames[0]) ==
          GUMBO_TOKENIZER_STATE_COUNT)
         ? 1
         : -1];
typedef char gumbo_token_type_list_check
    [(sizeof(kGumboTokenTypeValues) / sizeof(kGumboTokenTypeValues[0]) ==
          GUMBO_TOKEN_TYPE_COUNT &&
      sizeof(kGumboTokenTypeNames) / sizeof(kGumboTokenTypeNames[0]) ==
          GUMBO_TOKEN_TYPE_COUNT)
         ? 1
         : -1];
typedef char gumbo_insertion_mode_list_check
    [(sizeof(kGumboInsertionModeValues) /
              sizeof(kGumboInsertionModeValues[0]) ==
          GUMBO_INSERTION_MODE_COUNT &&
      sizeof(kGumboInsertionModeNames) / sizeof(kGumboInsertionModeNames[0]) ==
          GUMBO_INSERTION_MODE_COUNT)
         ? 1
         : -1];

/* Longest member name is GUMBO_INSERTION_RECONSTRUCTED_FORMATTING_ELEMENT
   (46 chars); 64 leaves headroom for a gumbo bump. */
#define GUMBO_ATOM_NAME_MAX 64

/* The mechanical rule: strip `prefix` from the raw member name, lowercase
   ASCII, keep underscores. Returns 1 on success, 0 if raw doesn't start with
   prefix (a member copied from the wrong family) or doesn't fit. */
static int gumbo_atom_name(char* name, size_t capacity, const char* raw,
                           const char* prefix) {
  size_t prefix_len = strlen(prefix);
  if (strncmp(raw, prefix, prefix_len) != 0) {
    return 0;
  }
  const char* src = raw + prefix_len;
  size_t i;
  for (i = 0;; ++i) {
    if (i + 1 >= capacity) {
      return 0;
    }
    unsigned char c = (unsigned char)src[i];
    if (c == '\0') {
      name[i] = '\0';
      return 1;
    }
    name[i] = (char)((c >= 'A' && c <= 'Z') ? c + ('a' - 'A') : c);
  }
}

/* Interning the value-indexed family. The table slot is keyed by the member's
   own enum value, so a reordered list cannot corrupt the mapping; a member
   whose value is out of range (only possible for a cross-family typo, which
   the prefix check catches first) fails the load instead of writing out of
   bounds. */
static int gumbo_atoms_init_family(ErlNifEnv* env, ERL_NIF_TERM* dest,
                                   size_t dest_count, const int* values,
                                   const char* const* raw_names, size_t count,
                                   const char* prefix) {
  char name[GUMBO_ATOM_NAME_MAX];
  size_t i;
  for (i = 0; i < count; ++i) {
    if (!gumbo_atom_name(name, sizeof(name), raw_names[i], prefix)) {
      return 1;
    }
    int value = values[i];
    if (value < 0 || (size_t)value >= dest_count) {
      return 1;
    }
    dest[value] = enif_make_atom(env, name);
  }
  return 0;
}

int gumbo_atoms_init(ErlNifEnv* env, gumbo_atoms_t* atoms) {
  int i;

  if (gumbo_atoms_init_family(env, atoms->node_types, GUMBO_NODE_TYPE_COUNT,
                              kGumboNodeTypeValues, kGumboNodeTypeNames,
                              GUMBO_NODE_TYPE_COUNT, "GUMBO_NODE_") != 0) {
    return 1;
  }
  if (gumbo_atoms_init_family(env, atoms->namespaces, GUMBO_NAMESPACE_COUNT,
                              kGumboNamespaceValues, kGumboNamespaceNames,
                              GUMBO_NAMESPACE_COUNT, "GUMBO_NAMESPACE_") != 0) {
    return 1;
  }
  if (gumbo_atoms_init_family(
          env, atoms->attribute_namespaces, GUMBO_ATTR_NAMESPACE_COUNT,
          kGumboAttrNamespaceValues, kGumboAttrNamespaceNames,
          GUMBO_ATTR_NAMESPACE_COUNT, "GUMBO_ATTR_NAMESPACE_") != 0) {
    return 1;
  }
  if (gumbo_atoms_init_family(env, atoms->quirks_modes, GUMBO_QUIRKS_MODE_COUNT,
                              kGumboQuirksModeValues, kGumboQuirksModeNames,
                              GUMBO_QUIRKS_MODE_COUNT, "GUMBO_DOCTYPE_") != 0) {
    return 1;
  }
  if (gumbo_atoms_init_family(
          env, atoms->parse_flags, GUMBO_PARSE_FLAG_TABLE_SIZE,
          kGumboParseFlagValues, kGumboParseFlagNames, GUMBO_PARSE_FLAG_COUNT,
          "GUMBO_INSERTION_") != 0) {
    return 1;
  }
  if (gumbo_atoms_init_family(env, atoms->error_types, GUMBO_ERROR_TYPE_COUNT,
                              kGumboErrorTypeValues, kGumboErrorTypeNames,
                              GUMBO_ERROR_TYPE_COUNT, "GUMBO_ERR_") != 0) {
    return 1;
  }
  if (gumbo_atoms_init_family(
          env, atoms->tokenizer_states, GUMBO_TOKENIZER_STATE_COUNT,
          kGumboTokenizerStateValues, kGumboTokenizerStateNames,
          GUMBO_TOKENIZER_STATE_COUNT, "GUMBO_ERR_TOKENIZER_") != 0) {
    return 1;
  }
  if (gumbo_atoms_init_family(env, atoms->token_types, GUMBO_TOKEN_TYPE_COUNT,
                              kGumboTokenTypeValues, kGumboTokenTypeNames,
                              GUMBO_TOKEN_TYPE_COUNT, "GUMBO_TOKEN_") != 0) {
    return 1;
  }
  if (gumbo_atoms_init_family(
          env, atoms->insertion_modes, GUMBO_INSERTION_MODE_COUNT,
          kGumboInsertionModeValues, kGumboInsertionModeNames,
          GUMBO_INSERTION_MODE_COUNT, "GUMBO_INSERTION_MODE_") != 0) {
    return 1;
  }

  /* Tags are the one exception to the mechanical rule. The names come from
     gumbo's own static table, but gumbo_normalized_tagname(GUMBO_TAG_UNKNOWN)
     returns "" — the empty string is not a tag name — so :unknown is
     special-cased. These atoms are created here, so enif_make_atom is the
     right call (enif_make_existing_atom would fail on a fresh VM). The
     names themselves are not cached: binaries created in the load callback's
     environment dangle once load returns, so gumbo_nif_tag_name copies the
     name into a fresh binary per call. */
  for (i = 0; i < GUMBO_TAG_COUNT; ++i) {
    const char* name = gumbo_normalized_tagname((GumboTag)i);
    atoms->tags[i] = (i == GUMBO_TAG_UNKNOWN) ? enif_make_atom(env, "unknown")
                                              : enif_make_atom(env, name);
  }

  atoms->ok = enif_make_atom(env, "ok");
  atoms->error = enif_make_atom(env, "error");
  atoms->true_ = enif_make_atom(env, "true");
  atoms->false_ = enif_make_atom(env, "false");
  atoms->nil = enif_make_atom(env, "nil");
  atoms->not_a_tag = enif_make_atom(env, "not_a_tag");

  atoms->tab_stop = enif_make_atom(env, "tab_stop");
  atoms->stop_on_first_error = enif_make_atom(env, "stop_on_first_error");
  atoms->max_errors = enif_make_atom(env, "max_errors");
  atoms->max_attributes = enif_make_atom(env, "max_attributes");
  atoms->max_tree_depth = enif_make_atom(env, "max_tree_depth");
  atoms->fragment_context = enif_make_atom(env, "fragment_context");
  atoms->fragment_namespace = enif_make_atom(env, "fragment_namespace");
  atoms->dirty = enif_make_atom(env, "dirty");
  atoms->auto_ = enif_make_atom(env, "auto");
  atoms->invalid_handle = enif_make_atom(env, "invalid_handle");
  atoms->invalid_option = enif_make_atom(env, "invalid_option");
  atoms->input_too_large = enif_make_atom(env, "input_too_large");
  atoms->too_many_attributes = enif_make_atom(env, "too_many_attributes");
  atoms->too_deep = enif_make_atom(env, "too_deep");
  atoms->tree_too_deep = enif_make_atom(env, "tree_too_deep");

  /* Node accessors: details-map keys named after the accessors they feed,
     the %Gumbo.Position{} struct keys, and the error atoms. */
  atoms->node.type = enif_make_atom(env, "type");
  atoms->node.index_within_parent = enif_make_atom(env, "index_within_parent");
  atoms->node.parse_flags = enif_make_atom(env, "parse_flags");
  atoms->node.position = enif_make_atom(env, "position");
  atoms->node.has_doctype = enif_make_atom(env, "has_doctype");
  atoms->node.doctype_name = enif_make_atom(env, "doctype_name");
  atoms->node.public_identifier = enif_make_atom(env, "public_identifier");
  atoms->node.system_identifier = enif_make_atom(env, "system_identifier");
  atoms->node.quirks_mode = enif_make_atom(env, "quirks_mode");
  atoms->node.tag = enif_make_atom(env, "tag");
  atoms->node.tag_name = enif_make_atom(env, "tag_name");
  atoms->node.namespace = enif_make_atom(env, "namespace");
  atoms->node.original_tag = enif_make_atom(env, "original_tag");
  atoms->node.original_end_tag = enif_make_atom(env, "original_end_tag");
  atoms->node.end_position = enif_make_atom(env, "end_position");
  atoms->node.text = enif_make_atom(env, "text");
  atoms->node.original_text = enif_make_atom(env, "original_text");
  atoms->node.target = enif_make_atom(env, "target");
  atoms->node.data = enif_make_atom(env, "data");
  /* Materialize's renames of :position and :doctype_name, plus the two keys
     only the materialized maps carry. The values are still the shared
     extractors' output, so the renames change names, never data. */
  atoms->node.start_position = enif_make_atom(env, "start_position");
  atoms->node.name = enif_make_atom(env, "name");
  atoms->node.attributes = enif_make_atom(env, "attributes");
  atoms->node.children = enif_make_atom(env, "children");
  atoms->node.struct_ = enif_make_atom(env, "__struct__");
  atoms->node.position_module = enif_make_atom(env, "Elixir.Gumbo.Position");
  atoms->node.line = enif_make_atom(env, "line");
  atoms->node.column = enif_make_atom(env, "column");
  atoms->node.offset = enif_make_atom(env, "offset");
  atoms->node.argument_error_module =
      enif_make_atom(env, "Elixir.ArgumentError");
  atoms->node.exception_ = enif_make_atom(env, "__exception__");
  atoms->node.message = enif_make_atom(env, "message");
  atoms->node.invalid_node = enif_make_atom(env, "invalid_node");

  /* Materialize result-map keys. */
  atoms->materialize.document = enif_make_atom(env, "document");
  atoms->materialize.root = enif_make_atom(env, "root");
  atoms->materialize.errors = enif_make_atom(env, "errors");

  /* Attribute accessors: details-map keys and the error atom. */
  atoms->attribute.namespace = enif_make_atom(env, "namespace");
  atoms->attribute.name = enif_make_atom(env, "name");
  atoms->attribute.value = enif_make_atom(env, "value");
  atoms->attribute.original_name = enif_make_atom(env, "original_name");
  atoms->attribute.original_value = enif_make_atom(env, "original_value");
  atoms->attribute.name_start = enif_make_atom(env, "name_start");
  atoms->attribute.name_end = enif_make_atom(env, "name_end");
  atoms->attribute.value_start = enif_make_atom(env, "value_start");
  atoms->attribute.value_end = enif_make_atom(env, "value_end");
  atoms->attribute.invalid_attribute = enif_make_atom(env, "invalid_attribute");

  /* Error accessors: details-map keys and the type-specific submap keys. */
  atoms->error_.type = enif_make_atom(env, "type");
  atoms->error_.position = enif_make_atom(env, "position");
  atoms->error_.original_text = enif_make_atom(env, "original_text");
  atoms->error_.message = enif_make_atom(env, "message");
  atoms->error_.caret = enif_make_atom(env, "caret");
  atoms->error_.codepoint = enif_make_atom(env, "codepoint");
  atoms->error_.tokenizer = enif_make_atom(env, "tokenizer");
  atoms->error_.text = enif_make_atom(env, "text");
  atoms->error_.duplicate_attr = enif_make_atom(env, "duplicate_attr");
  atoms->error_.parser_error = enif_make_atom(env, "parser_error");
  atoms->error_.state = enif_make_atom(env, "state");
  atoms->error_.name = enif_make_atom(env, "name");
  atoms->error_.original_index = enif_make_atom(env, "original_index");
  atoms->error_.new_index = enif_make_atom(env, "new_index");
  atoms->error_.input_type = enif_make_atom(env, "input_type");
  atoms->error_.input_tag = enif_make_atom(env, "input_tag");
  atoms->error_.insertion_mode = enif_make_atom(env, "insertion_mode");
  atoms->error_.tag_stack = enif_make_atom(env, "tag_stack");

  return 0;
}
