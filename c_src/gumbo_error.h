#ifndef GUMBO_ERROR_NIF_H_
#define GUMBO_ERROR_NIF_H_

#include <erl_nif.h>

#include "gumbo_atoms.h"
#include "gumbo_handle.h"

/* Gumbo.Error accessor surface. output_errors lists the indices into
   output->errors in source order ([] when the parse reported nothing);
   error_details resolves an error index with bounds checking and answers
   {:ok, map} on success or {:error, :invalid_node} for a non-handle or an
   index outside output->errors. The Elixir-side scalar accessors project
   one field out of the map and raise ArgumentError on the error. Nothing
   dereferences an unchecked index. */
ERL_NIF_TERM gumbo_nif_output_errors(ErlNifEnv* env,
                                     const gumbo_atoms_t* atoms, int argc,
                                     const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_error_details(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     int argc, const ERL_NIF_TERM argv[]);

/* The full error map, built from the one-extractor-per-field builders.
   Exported so gumbo_materialize.c's errors list comes from the same
   builder as error_details, and the two surfaces cannot disagree. */
int gumbo_error_details_map(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                            const gumbo_handle_t* h, const GumboError* error,
                            ERL_NIF_TERM* out);

#endif /* GUMBO_ERROR_NIF_H_ */
