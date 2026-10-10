#include <limits.h>
#include <string.h>

#include "gumbo.h"
#include "gumbo_tags.h"

/* All five asserts reachable from gumbo's public tag API are guarded in this
   file: gumbo_normalized_tagname asserts on its range, and
   gumbo_tag_from_original_text asserts on all four of its preconditions.
   Asserts are live in our build (NDEBUG is not defined), so a violation
   aborts the VM. The other three functions (gumbo_tagn_enum,
   gumbo_tag_is_void, gumbo_normalize_svg_tagname) are assert-free. */

/* tag_name/1: the argument is either a tag atom (resolved by identity over
   the interned tag table) or a raw enum integer. Out-of-range integers get
   nil — gumbo_normalized_tagname's assert(tag <= GUMBO_TAG_LAST) would abort
   the VM. The name comes from gumbo's own static table and is copied into a
   fresh binary in the caller's environment on every call; caching it at load
   time would return a term whose environment has died. */
static ERL_NIF_TERM gumbo_tag_name_binary(ErlNifEnv* env, GumboTag tag) {
  const char* name = gumbo_normalized_tagname(tag);
  size_t len = strlen(name);
  ERL_NIF_TERM out;
  unsigned char* buf = enif_make_new_binary(env, len, &out);
  if (buf == NULL) {
    /* Allocation failure surfaces as an ArgumentError; it is unreachable in
       practice and this path must not create atoms. */
    return enif_raise_exception(env, enif_make_badarg(env));
  }
  if (len > 0) {
    memcpy(buf, name, len);
  }
  return out;
}

ERL_NIF_TERM gumbo_nif_tag_name(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                            int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  if (enif_is_atom(env, argv[0])) {
    int i;
    for (i = 0; i < GUMBO_TAG_COUNT; ++i) {
      if (enif_is_identical(argv[0], atoms->tags[i])) {
        return gumbo_tag_name_binary(env, (GumboTag)i);
      }
    }
    return atoms->nil; /* an atom that is not a tag */
  }

  int tag;
  if (!enif_get_int(env, argv[0], &tag)) {
    return enif_make_badarg(env);
  }
  /* Mirrors gumbo's assert range exactly, including GUMBO_TAG_LAST (whose
     normalized name is ""). */
  if (tag < 0 || tag > GUMBO_TAG_LAST) {
    return atoms->nil;
  }
  return gumbo_tag_name_binary(env, (GumboTag)tag);
}

/* from_name/1: gumbo_tagn_enum is length-aware and case-insensitive, so the
   binary needs no NUL terminator and any bytes (including embedded NULs) are
   safe. */
ERL_NIF_TERM gumbo_nif_tag_from_name(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                 int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  ErlNifBinary bin;
  if (!enif_inspect_binary(env, argv[0], &bin)) {
    return enif_make_badarg(env);
  }
  /* gumbo_tagn_enum takes an unsigned int length; a longer binary would
     silently truncate and could match the wrong tag. */
  if (bin.size > UINT_MAX) {
    return atoms->tags[GUMBO_TAG_UNKNOWN];
  }
  GumboTag tag =
      gumbo_tagn_enum((const char*)bin.data, (unsigned int)bin.size);
  return atoms->tags[tag];
}

/* void?/1: no assert here — gumbo_tag_is_void's switch has a default branch,
   so any integer is safe and simply reports false. */
ERL_NIF_TERM gumbo_nif_tag_void(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                            int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  if (enif_is_atom(env, argv[0])) {
    int i;
    for (i = 0; i < GUMBO_TAG_COUNT; ++i) {
      if (enif_is_identical(argv[0], atoms->tags[i])) {
        return gumbo_tag_is_void((GumboTag)i) ? atoms->true_ : atoms->false_;
      }
    }
    return atoms->false_; /* an atom that is not a tag is not void */
  }

  int tag;
  if (!enif_get_int(env, argv[0], &tag)) {
    return enif_make_badarg(env);
  }
  return gumbo_tag_is_void((GumboTag)tag) ? atoms->true_ : atoms->false_;
}

/* svg_name/1: gumbo_normalize_svg_tagname is assert-free and compares by
   explicit length (gumbo_string_equals_ignore_case), so the binary needs no
   NUL terminator. NULL means no replacement. */
ERL_NIF_TERM gumbo_nif_tag_svg_name(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;

  ErlNifBinary bin;
  if (!enif_inspect_binary(env, argv[0], &bin)) {
    return enif_make_badarg(env);
  }

  GumboStringPiece piece;
  piece.data = (const char*)bin.data;
  piece.length = (size_t)bin.size;
  const char* name = gumbo_normalize_svg_tagname(&piece);
  if (name == NULL) {
    return atoms->nil;
  }
  /* Static, NUL-terminated data owned by gumbo. */
  ERL_NIF_TERM out;
  if (!gumbo_make_binary(env, name, strlen(name), &out)) {
    /* Allocation failure surfaces as an ArgumentError; it is unreachable in
       practice and this path must not create atoms. */
    return enif_raise_exception(env, enif_make_badarg(env));
  }
  return out;
}

/* from_original_text/1: gumbo_tag_from_original_text asserts on all four of
   its preconditions (length >= 2, data[0] == '<', data[length-1] == '>',
   length >= 3 when data[1] == '/') and documents anything else as undefined
   behaviour, so gumbo is called only on a piece that provably satisfies
   them. One further check of our own rejects an empty extracted name: "<>"
   and "</>" pass gumbo's asserts but yield "", which is not a tag. Anything
   that is not a complete tag yields {:error, :not_a_tag}. gumbo mutates the
   piece struct, never the buffer, so the binary's bytes are only read. */
ERL_NIF_TERM gumbo_nif_tag_from_original_text(ErlNifEnv* env,
                                          const gumbo_atoms_t* atoms, int argc,
                                          const ERL_NIF_TERM argv[]) {
  (void)argc;

  ErlNifBinary bin;
  if (!enif_inspect_binary(env, argv[0], &bin)) {
    return enif_make_badarg(env);
  }
  const char* data = (const char*)bin.data;
  size_t len = bin.size;

  if (len < 2 || data[0] != '<' || data[len - 1] != '>' ||
      (data[1] == '/' && len < 3)) {
    return enif_make_tuple2(env, atoms->error, atoms->not_a_tag);
  }

  GumboStringPiece piece;
  piece.data = data;
  piece.length = len;
  gumbo_tag_from_original_text(&piece);
  if (piece.length == 0) {
    return enif_make_tuple2(env, atoms->error, atoms->not_a_tag);
  }
  ERL_NIF_TERM name_term;
  if (!gumbo_make_binary(env, piece.data, piece.length, &name_term)) {
    return enif_raise_exception(env, enif_make_badarg(env));
  }
  return enif_make_tuple2(env, atoms->ok, name_term);
}

/* all/0: the interned tag atoms in enum order, consed from the end so the
   list stays ascending without an intermediate allocation. */
ERL_NIF_TERM gumbo_nif_tag_all(ErlNifEnv* env, const gumbo_atoms_t* atoms, int argc,
                           const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;

  ERL_NIF_TERM list = enif_make_list(env, 0);
  int i;
  for (i = GUMBO_TAG_COUNT - 1; i >= 0; --i) {
    list = enif_make_list_cell(env, atoms->tags[i], list);
  }
  return list;
}
