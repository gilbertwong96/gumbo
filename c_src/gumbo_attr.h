#ifndef GUMBO_ATTR_H_
#define GUMBO_ATTR_H_

#include <erl_nif.h>

#include "gumbo_atoms.h"

/* Gumbo.Attribute accessor surface. attr_details resolves the (node,
   attribute) index pair with bounds checking and answers {:ok, map} on
   success, {:error, :invalid_node} for a node index outside the handle's
   table, or {:error, :invalid_attribute} for an attribute index outside the
   element's attribute vector; the Elixir-side scalar accessors project one
   field out of the map and raise ArgumentError on either error. Nothing
   dereferences an unchecked index. */
ERL_NIF_TERM gumbo_nif_attr_details(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    int argc, const ERL_NIF_TERM argv[]);

#endif /* GUMBO_ATTR_H_ */
