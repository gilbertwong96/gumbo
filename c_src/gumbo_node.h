#ifndef GUMBO_NODE_H_
#define GUMBO_NODE_H_

#include <erl_nif.h>

#include "gumbo.h"
#include "gumbo_atoms.h"

/* Gumbo.Node accessors, one NIF per entry point. The scalar accessors are
   Elixir-side projections of the node_details map, so they share every
   extractor with it by construction; node_children, node_parent, node_next
   and node_previous return node indices (nil at the ends), node_attributes
   returns attribute indices ([] off elements) and node_attribute runs
   gumbo_get_attribute's case-insensitive lookup. A node index that is not
   in the handle's table is a programmer error: node_details answers
   {:error, :invalid_node} and the other accessors raise ArgumentError,
   which is what keeps their typespecs clean. Nothing dereferences an
   unchecked index. */
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
ERL_NIF_TERM gumbo_nif_node_attributes(ErlNifEnv* env,
                                       const gumbo_atoms_t* atoms, int argc,
                                       const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_node_attribute(ErlNifEnv* env,
                                      const gumbo_atoms_t* atoms, int argc,
                                      const ERL_NIF_TERM argv[]);

/* Small builders shared with gumbo_attr.c, which resolves a GumboAttribute
   through the same node table: the element/template predicate, the
   NUL-terminated-string and string-piece extractors, and the
   %Gumbo.Position{} map. They stay exported so an attribute field is
   extracted by exactly the same code path as a node field. */
int gumbo_node_is_element(const GumboNode* node);
ERL_NIF_TERM gumbo_node_stringz(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                const char* s);
ERL_NIF_TERM gumbo_node_string_piece(ErlNifEnv* env, GumboStringPiece piece);
int gumbo_node_position_map(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                            GumboSourcePosition pos, ERL_NIF_TERM* out);

#endif /* GUMBO_NODE_H_ */
