#ifndef GUMBO_MATERIALIZE_H_
#define GUMBO_MATERIALIZE_H_

#include <erl_nif.h>

#include "gumbo_atoms.h"

/* The two materialize NIFs. detail is 0 for :full (the default) and 1 for
   :content; the Elixir side validates the atom and passes the code.
   materialize_output answers %{document:, root:, errors:} — root: nil when
   the parse stopped before any element was built — (or {:error,
   :invalid_handle} for a non-handle) and materialize_node answers {:ok,
   map} | {:error, :invalid_node}, the same invalid-node contract
   node_details uses. Both walk the handle's preorder node table in one
   reverse loop, building each node's map from its already-built children
   and storing terms in a scratch ERL_NIF_TERM[] of node_count entries, so
   depth costs memory, never C stack. */
ERL_NIF_TERM gumbo_nif_materialize_output(ErlNifEnv* env,
                                          const gumbo_atoms_t* atoms, int argc,
                                          const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_materialize_node(ErlNifEnv* env,
                                        const gumbo_atoms_t* atoms, int argc,
                                        const ERL_NIF_TERM argv[]);

#endif /* GUMBO_MATERIALIZE_H_ */
