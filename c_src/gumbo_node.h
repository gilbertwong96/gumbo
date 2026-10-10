#ifndef GUMBO_NODE_H_
#define GUMBO_NODE_H_

#include <erl_nif.h>

#include "gumbo.h"
#include "gumbo_atoms.h"

/* Gumbo.Node accessors, one NIF per entry point. The scalar accessors are
   Elixir-side projections of the node_details map, so they share every
   extractor with it by construction; node_children, node_parent, node_next
   and node_previous return node indices (nil at the ends). A node index that
   is not in the handle's table is a programmer error: node_details answers
   {:error, :invalid_node} and the other four raise ArgumentError, which is
   what keeps their typespecs clean. Nothing dereferences an unchecked
   index. */
ERL_NIF_TERM gumbo_nif_node_details(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_node_children(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_node_parent(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                   int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_node_next(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                 int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_node_previous(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                     int argc, const ERL_NIF_TERM argv[]);

#endif /* GUMBO_NODE_H_ */
