#ifndef GUMBO_OPTIONS_H_
#define GUMBO_OPTIONS_H_

#include <erl_nif.h>

#include "gumbo_atoms.h"
#include "gumbo_handle.h"

/* Decodes the map produced by Gumbo.Options.to_nif/1 into h->options and
   h->dirty. to_nif/1 always emits every key with a new/1-validated value, so
   a missing key or an undecodable value cannot happen through the public
   API. Returns 1 on success; on failure returns 0 and the caller answers
   {:error, :invalid_option}. */
int gumbo_options_decode(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                         ERL_NIF_TERM options_map, gumbo_handle_t* h);

/* Encodes h->options and h->dirty back into the to_nif/1 shape. Returns 1 on
   success; on failure returns 0 and the caller raises an allocation error. */
int gumbo_options_encode(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                         const gumbo_handle_t* h, ERL_NIF_TERM* out);

#endif /* GUMBO_OPTIONS_H_ */
