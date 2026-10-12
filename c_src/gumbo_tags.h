#ifndef GUMBO_TAGS_H_
#define GUMBO_TAGS_H_

#include <erl_nif.h>

#include "gumbo_atoms.h"

/* The six tag NIFs. Each takes the interned atom tables as a parameter;
   gumbo_nif.c wraps them into the registered ErlNifFunc entries. */

ERL_NIF_TERM gumbo_nif_tag_name(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                int argc, const ERL_NIF_TERM argv[]);

ERL_NIF_TERM gumbo_nif_tag_from_name(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     int argc, const ERL_NIF_TERM argv[]);

ERL_NIF_TERM gumbo_nif_tag_void(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                int argc, const ERL_NIF_TERM argv[]);

ERL_NIF_TERM gumbo_nif_tag_svg_name(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    int argc, const ERL_NIF_TERM argv[]);

ERL_NIF_TERM gumbo_nif_tag_from_original_text(ErlNifEnv* env,
                                              const gumbo_atoms_t* atoms,
                                              int argc,
                                              const ERL_NIF_TERM argv[]);

ERL_NIF_TERM gumbo_nif_tag_all(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                               int argc, const ERL_NIF_TERM argv[]);

#endif /* GUMBO_TAGS_H_ */
