#include "gumbo_error.h"

#include <string.h>

#include "error.h" /* gumbo's internal header; see the note below */
#include "gumbo.h"
#include "gumbo_atoms.h"
#include "gumbo_faults.h"
#include "gumbo_handle.h"
#include "gumbo_node.h"
#include "parser.h"
#include "util.h" /* gumbo_parser_deallocate, for the rendered buffer */

/* This file owns the GumboError surface: output_errors lists the indices
   into output->errors and error_details assembles the full map from one
   extractor per field, exactly as gumbo_node.c and gumbo_attr.c do, so a
   field cannot be right in one place and wrong in another. Every term is
   built in the caller's environment per call; the shared string, piece and
   position extractors are the same helpers node and attribute fields use.

   error.h is gumbo's internal header — the public gumbo.h exposes
   output->errors only as an opaque GumboVector — and this is the one place
   we read it. That is safe because the submodule pins gumbo-parser to
   0.14.1, and gumbo_atoms.c's compile-time enum checks fail loudly on a
   bump. The GumboError.v union is read strictly by type, per error.h:
   codepoint (UTF8_INVALID/TRUNCATED and the numeric char-ref errors),
   tokenizer (the tokenizer-state errors), text (the named char-ref
   errors), duplicate_attr (DUPLICATE_ATTR), parser (PARSER and
   UNACKNOWLEDGED_SELF_CLOSING_TAG); every other member of the union is
   garbage for that type.

   message and caret render through gumbo_error_to_string /
   gumbo_caret_diagnostic_to_string with a stack-local GumboParser carrying
   only _options, the same trick gumbo_destroy_output uses. Verified at
   0.14.1: nothing on that formatting path touches parser except
   parser->_options, reached through print_message and the
   gumbo_string_buffer_* helpers. The rendered buffer is allocated with
   gumbo's allocator, so it is freed with gumbo_parser_deallocate, never
   enif_free. caret/1's source_text must be the very buffer the parse used
   — h->input_data — because the diagnostic walks outwards from
   error->original_text, a pointer into it; that copy is NUL-terminated
   (gumbo_handle.c) because the walk stops at the first NUL. */

/* ---- resolution ---- */

/* An error index outside output->errors is a programmer error: error_details
   answers {:error, :invalid_node} (the same atom node and attribute details
   use) and the Elixir-side scalar accessors raise ArgumentError on it.
   Nothing dereferences an unchecked index. */

/* ---- one extractor per details-map field ---- */

/* Every extractor answers success as a status code with the term in *out
   rather than returning a term: a badarg sentinel returned from inside the
   details-map assembly would be embedded into the map as the integer 42
   rather than surfaced, so a failure must propagate as 0 up to the NIF. An
   extractor that cannot fail answers 1 like the rest, because a convention
   with exceptions is a convention a reader has to check against. */

static int gumbo_error_type_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                 const GumboError* error, ERL_NIF_TERM* out) {
#ifdef GUMBO_TEST_FAULTS
  if (gumbo_fault_should_fail()) {
    /* A failure, on purpose: see gumbo_faults.h. */
    return GUMBO_FAULT_FAILURE(env, out);
  }
#endif

  (void)env;
  /* Parser-produced, so the table index is in range by construction. */
  *out = atoms->error_types[error->type];
  return 1;
}

static int gumbo_error_position_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     const GumboError* error,
                                     ERL_NIF_TERM* out) {
  return gumbo_node_position_map(env, atoms, error->position, out);
}

/* The source bytes from the error location to the end of the input: the
   pointer identifies a position, not a length, and the retained copy's size
   is what bounds it. Returned as a sub-binary of the retained copy so the
   bytes are shared rather than copied — the length is everything from the
   error to EOF, so copying it once per error costs the error count times
   the document size, which is quadratic for error-dense input. The guard is
   unreachable — every producer sets original_text inside the buffer — and
   degrades to the empty binary rather than dereferencing, as does the
   zero-length tail, which also avoids a zero-length sub-binary. */
static int gumbo_error_original_text_term(ErlNifEnv* env,
                                          const gumbo_atoms_t* atoms,
                                          const gumbo_handle_t* h,
                                          const GumboError* error,
                                          ERL_NIF_TERM* out) {
  (void)atoms;
  const char* start = h->input_data;
  const char* end = start + h->input_size;
  if (error->original_text == NULL || error->original_text < start ||
      error->original_text > end) {
    return gumbo_make_binary(env, NULL, 0, out);
  }
  size_t pos = (size_t)(error->original_text - start);
  if (pos >= h->input_size) {
    return gumbo_make_binary(env, NULL, 0, out);
  }
  /* The parent has to be a term in the calling env: a term owned by a
     process-independent env cannot parent a sub-binary, and passing one
     crashes inside erts_build_sub_bitstring. */
  ERL_NIF_TERM parent = enif_make_copy(env, h->input_term);
  *out = enif_make_sub_binary(env, parent, pos, h->input_size - pos);
  return 1;
}

/* Renders the error with one of gumbo's two string builders and copies the
   result into a fresh binary before freeing the buffer with gumbo's own
   deallocator. caret selects gumbo_caret_diagnostic_to_string, which reads
   source bytes around error->original_text, so the buffer handed in is the
   one the parse used. */
static int gumbo_error_render_term(ErlNifEnv* env, const gumbo_handle_t* h,
                                   const GumboError* error, int caret,
                                   ERL_NIF_TERM* out) {
  GumboParser parser;
  memset(&parser, 0, sizeof(parser));
  parser._options = &h->options;
  GumboStringBuffer buffer;
  gumbo_string_buffer_init(&parser, &buffer);
  if (caret) {
    gumbo_caret_diagnostic_to_string(&parser, error, h->input_data, &buffer);
  } else {
    gumbo_error_to_string(&parser, error, &buffer);
  }
  int ok = gumbo_make_binary(env, buffer.data, buffer.length, out);
  gumbo_parser_deallocate(&parser, buffer.data);
  return ok;
}

static int gumbo_error_codepoint_term(ErlNifEnv* env,
                                      const gumbo_atoms_t* atoms,
                                      const GumboError* error,
                                      ERL_NIF_TERM* out) {
  switch (error->type) {
    case GUMBO_ERR_UTF8_INVALID:
    case GUMBO_ERR_UTF8_TRUNCATED:
    case GUMBO_ERR_NUMERIC_CHAR_REF_WITHOUT_SEMICOLON:
    case GUMBO_ERR_NUMERIC_CHAR_REF_INVALID:
      *out = enif_make_uint64(env, error->v.codepoint);
      return 1;
    default:
      *out = atoms->nil;
      return 1;
  }
}

/* The tokenizer-state errors, the exact set tokenizer_add_parse_error
   produces at 0.14.1 (tokenizer.c). codepoint is the raw int under the
   cursor, which can be -1 at EOF. */
static int gumbo_error_tokenizer_term(ErlNifEnv* env,
                                      const gumbo_atoms_t* atoms,
                                      const GumboError* error,
                                      ERL_NIF_TERM* out) {
  switch (error->type) {
    case GUMBO_ERR_UTF8_NULL:
    case GUMBO_ERR_TAG_EOF:
    case GUMBO_ERR_TAG_INVALID:
    case GUMBO_ERR_CLOSE_TAG_EMPTY:
    case GUMBO_ERR_CLOSE_TAG_EOF:
    case GUMBO_ERR_CLOSE_TAG_INVALID:
    case GUMBO_ERR_SCRIPT_EOF:
    case GUMBO_ERR_ATTR_NAME_EOF:
    case GUMBO_ERR_ATTR_NAME_INVALID:
    case GUMBO_ERR_ATTR_DOUBLE_QUOTE_EOF:
    case GUMBO_ERR_ATTR_SINGLE_QUOTE_EOF:
    case GUMBO_ERR_ATTR_UNQUOTED_EOF:
    case GUMBO_ERR_ATTR_UNQUOTED_RIGHT_BRACKET:
    case GUMBO_ERR_ATTR_UNQUOTED_EQUALS:
    case GUMBO_ERR_ATTR_AFTER_EOF:
    case GUMBO_ERR_ATTR_AFTER_INVALID:
    case GUMBO_ERR_SOLIDUS_EOF:
    case GUMBO_ERR_SOLIDUS_INVALID:
    case GUMBO_ERR_DASHES_OR_DOCTYPE:
    case GUMBO_ERR_COMMENT_EOF:
    case GUMBO_ERR_COMMENT_INVALID:
    case GUMBO_ERR_COMMENT_BANG_AFTER_DOUBLE_DASH:
    case GUMBO_ERR_COMMENT_DASH_AFTER_DOUBLE_DASH:
    case GUMBO_ERR_COMMENT_SPACE_AFTER_DOUBLE_DASH:
    case GUMBO_ERR_COMMENT_END_BANG_EOF:
    case GUMBO_ERR_DOCTYPE_EOF:
    case GUMBO_ERR_DOCTYPE_INVALID:
    case GUMBO_ERR_DOCTYPE_SPACE:
    case GUMBO_ERR_DOCTYPE_RIGHT_BRACKET:
    case GUMBO_ERR_DOCTYPE_SPACE_OR_RIGHT_BRACKET:
    case GUMBO_ERR_DOCTYPE_END:
      break;
    default:
      *out = atoms->nil;
      return 1;
  }
  ERL_NIF_TERM keys[] = {atoms->error_.state, atoms->error_.codepoint};
  ERL_NIF_TERM values[] = {
      atoms->tokenizer_states[error->v.tokenizer.state],
      enif_make_int(env, error->v.tokenizer.codepoint),
  };
  return enif_make_map_from_arrays(env, keys, values, 2, out);
}

/* The named char-ref errors: text is a piece into the retained input (the
   bad reference as written). */
static int gumbo_error_text_term(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                 const GumboError* error, ERL_NIF_TERM* out) {
  switch (error->type) {
    case GUMBO_ERR_NAMED_CHAR_REF_WITHOUT_SEMICOLON:
    case GUMBO_ERR_NAMED_CHAR_REF_INVALID:
      break;
    default:
      *out = atoms->nil;
      return 1;
  }
  return gumbo_make_binary(env, error->v.text.data, error->v.text.length, out);
}

static int gumbo_error_duplicate_attr_term(ErlNifEnv* env,
                                           const gumbo_atoms_t* atoms,
                                           const GumboError* error,
                                           ERL_NIF_TERM* out) {
  if (error->type != GUMBO_ERR_DUPLICATE_ATTR) {
    *out = atoms->nil;
    return 1;
  }
  const GumboDuplicateAttrError* dup = &error->v.duplicate_attr;
  ERL_NIF_TERM name;
  if (dup->name == NULL) {
    name = atoms->nil;
  } else if (!gumbo_make_binary(env, dup->name, strlen(dup->name), &name)) {
    return 0;
  }
  ERL_NIF_TERM keys[] = {atoms->error_.name, atoms->error_.original_index,
                         atoms->error_.new_index};
  ERL_NIF_TERM values[] = {
      name,
      enif_make_uint(env, dup->original_index),
      enif_make_uint(env, dup->new_index),
  };
  return enif_make_map_from_arrays(env, keys, values, 3, out);
}

static int gumbo_error_parser_error_term(ErlNifEnv* env,
                                         const gumbo_atoms_t* atoms,
                                         const GumboError* error,
                                         ERL_NIF_TERM* out) {
#ifdef GUMBO_TEST_FAULTS
  if (gumbo_fault_should_fail()) {
    /* A failure, on purpose: see gumbo_faults.h. */
    return GUMBO_FAULT_FAILURE(env, out);
  }
#endif

  switch (error->type) {
    case GUMBO_ERR_PARSER:
    case GUMBO_ERR_UNACKNOWLEDGED_SELF_CLOSING_TAG:
      break;
    default:
      *out = atoms->nil;
      return 1;
  }
  const GumboParserError* parser = &error->v.parser;

  /* tag_stack is the one gumbo vector that stores its values by value: each
     void* slot is a GumboTag cast to a pointer (error.h says so, and
     error.c's print_tag_stack casts back the same way). Cons from the end so
     the list stays in stack order, bottom to top. */
  ERL_NIF_TERM stack = enif_make_list(env, 0);
  unsigned int i;
  for (i = parser->tag_stack.length; i-- > 0;) {
    GumboTag tag = (GumboTag)(intptr_t)parser->tag_stack.data[i];
    stack = enif_make_list_cell(env, atoms->tags[tag], stack);
  }

  ERL_NIF_TERM keys[] = {atoms->error_.input_type, atoms->error_.input_tag,
                         atoms->error_.insertion_mode, atoms->error_.tag_stack};
  ERL_NIF_TERM values[] = {
      atoms->token_types[parser->input_type],
      atoms->tags[parser->input_tag],
      atoms->insertion_modes[parser->parser_state],
      stack,
  };
  return enif_make_map_from_arrays(env, keys, values, 4, out);
}

/* ---- the NIF entry points ---- */

#define GUMBO_ERROR_FIELDS_COUNT 8
#define GUMBO_ERROR_MATERIALIZED_COUNT 9

/* The eight fields read off the error in place: type, position,
   original_text, codepoint, tokenizer, text, duplicate_attr, parser_error.
   None of them renders. That matters because rendering is the whole cost of
   a :parser error: print_message is variadic and print_tag_stack calls it
   twice per open tag, so a 200-deep tag stack costs ~30us per render and a
   caller asking only for the type must not pay it. */
static int gumbo_error_fields_values(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     const gumbo_handle_t* h,
                                     const GumboError* error,
                                     ERL_NIF_TERM values[]) {
  /* Each extraction is checked before its term joins the map: a value that
     stands for a failure would surface as the integer 42. Failure here is
     allocation failure, and it propagates to the NIF as badarg. */
  if (!gumbo_error_type_term(env, atoms, error, &values[0]) ||
      !gumbo_error_position_term(env, atoms, error, &values[1]) ||
      !gumbo_error_original_text_term(env, atoms, h, error, &values[2]) ||
      !gumbo_error_codepoint_term(env, atoms, error, &values[3]) ||
      !gumbo_error_tokenizer_term(env, atoms, error, &values[4]) ||
      !gumbo_error_text_term(env, atoms, error, &values[5]) ||
      !gumbo_error_duplicate_attr_term(env, atoms, error, &values[6]) ||
      !gumbo_error_parser_error_term(env, atoms, error, &values[7])) {
    return 0;
  }
  return 1;
}

/* The nine-field map materialize's errors list carries: the eight accessor
   fields plus the rendered message. Error.details/1 has a tenth, the rendered
   caret, and materialize deliberately does not — gumbo renders a caret as the
   whole source line with column-1 spaces, so one caret is O(line length), and
   materialize builds one of these maps per error. Measured on a 420 KB
   single-line document: 40 002 errors cost 426 KB of fresh binaries per 1 000
   errors, a 12.7 s call, and a ~17 GB term. caret/1 on a live error still
   renders it, one error at a time, and that is bounded by a single line. */
int gumbo_error_materialized_map(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                 const gumbo_handle_t* h,
                                 const GumboError* error, ERL_NIF_TERM* out) {
  ERL_NIF_TERM keys[GUMBO_ERROR_MATERIALIZED_COUNT] = {
      atoms->error_.type,           atoms->error_.position,
      atoms->error_.original_text,  atoms->error_.codepoint,
      atoms->error_.tokenizer,      atoms->error_.text,
      atoms->error_.duplicate_attr, atoms->error_.parser_error,
      atoms->error_.message,
  };
  ERL_NIF_TERM values[GUMBO_ERROR_MATERIALIZED_COUNT];
  if (!gumbo_error_fields_values(env, atoms, h, error, values) ||
      !gumbo_error_render_term(env, h, error, 0, &values[8])) {
    return 0;
  }
  return enif_make_map_from_arrays(env, keys, values,
                                   GUMBO_ERROR_MATERIALIZED_COUNT, out);
}

/* The same eight fields as a map of their own, so a scalar accessor never
   reaches gumbo_error_render_term. */
static int gumbo_error_fields_map(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                  const gumbo_handle_t* h,
                                  const GumboError* error, ERL_NIF_TERM* out) {
  ERL_NIF_TERM keys[GUMBO_ERROR_FIELDS_COUNT] = {
      atoms->error_.type,           atoms->error_.position,
      atoms->error_.original_text,  atoms->error_.codepoint,
      atoms->error_.tokenizer,      atoms->error_.text,
      atoms->error_.duplicate_attr, atoms->error_.parser_error,
  };
  ERL_NIF_TERM values[GUMBO_ERROR_FIELDS_COUNT];
  if (!gumbo_error_fields_values(env, atoms, h, error, values)) {
    return 0;
  }
  return enif_make_map_from_arrays(env, keys, values, GUMBO_ERROR_FIELDS_COUNT,
                                   out);
}

/* Resolves the (resource, index) pair the error accessors share. A forged or
   stale handle and an index outside output->errors are both programmer
   errors, and both answer {:error, :invalid_node}; *out holds that tuple
   when this reports failure. */
static int gumbo_error_resolve(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                               const ERL_NIF_TERM argv[], gumbo_handle_t** h,
                               const GumboError** error, ERL_NIF_TERM* out) {
  if (!gumbo_handle_get(env, argv[0], h)) {
    *out = enif_make_tuple2(env, atoms->error, atoms->node.invalid_node);
    return 0;
  }
  unsigned long index;
  if (!enif_get_ulong(env, argv[1], &index) ||
      index >= (*h)->output->errors.length) {
    *out = enif_make_tuple2(env, atoms->error, atoms->node.invalid_node);
    return 0;
  }
  *error = (*h)->output->errors.data[index];
  return 1;
}

ERL_NIF_TERM gumbo_nif_error_fields(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  const GumboError* error;
  ERL_NIF_TERM failure;
  if (!gumbo_error_resolve(env, atoms, argv, &h, &error, &failure)) {
    return failure;
  }

  ERL_NIF_TERM map;
  if (!gumbo_error_fields_map(env, atoms, h, error, &map)) {
    return enif_make_badarg(env);
  }
  return enif_make_tuple2(env, atoms->ok, map);
}

/* message (caret 0) and caret (caret 1) are the two fields that render, and
   they render differently enough to be worth separating: message is gumbo's
   own text, caret adds the whole source line plus column-1 spaces. Asking
   for one must not render the other. */
static ERL_NIF_TERM gumbo_nif_error_render(ErlNifEnv* env,
                                           const gumbo_atoms_t* atoms,
                                           const ERL_NIF_TERM argv[],
                                           int caret) {
  gumbo_handle_t* h;
  const GumboError* error;
  ERL_NIF_TERM failure;
  if (!gumbo_error_resolve(env, atoms, argv, &h, &error, &failure)) {
    return failure;
  }

  ERL_NIF_TERM binary;
  if (!gumbo_error_render_term(env, h, error, caret, &binary)) {
    return enif_make_badarg(env);
  }
  return enif_make_tuple2(env, atoms->ok, binary);
}

ERL_NIF_TERM gumbo_nif_error_message(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  return gumbo_nif_error_render(env, atoms, argv, 0);
}

ERL_NIF_TERM gumbo_nif_error_caret(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                   int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  return gumbo_nif_error_render(env, atoms, argv, 1);
}

ERL_NIF_TERM gumbo_nif_output_errors(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  gumbo_handle_t* h;
  if (!gumbo_handle_get(env, argv[0], &h)) {
    return enif_make_tuple2(env, atoms->error, atoms->invalid_handle);
  }

  ERL_NIF_TERM list = enif_make_list(env, 0);
  GumboVector* errors = &h->output->errors;
  /* Cons from the end so the list stays in source order. */
  unsigned int i;
  for (i = errors->length; i-- > 0;) {
    list = enif_make_list_cell(env, enif_make_ulong(env, i), list);
  }
  return list;
}
