#ifndef GUMBO_HANDLE_H_
#define GUMBO_HANDLE_H_

#include <stddef.h>

#include <erl_nif.h>

#include "gumbo.h"
#include "gumbo_atoms.h"

/* The :dirty option, decoded into the handle so output_options/1 can
   round-trip the full Gumbo.Options.t. It is this library's scheduler
   policy, not a gumbo field, so it cannot live in GumboOptions. */
typedef enum {
  GUMBO_DIRTY_AUTO = 0, /* :auto */
  GUMBO_DIRTY_NORMAL,   /* false  */
  GUMBO_DIRTY_FORCE     /* true   */
} gumbo_dirty_t;

typedef struct {
  GumboOptions options; /* by value: destroy_output re-reads the allocator */
  gumbo_dirty_t dirty;  /* the :dirty option, for options/1 round-tripping */
  GumboOutput* output;
  ErlNifBinary input; /* private copy: the tree points into it */
  GumboNode** nodes;  /* preorder; node identity is an index into this */
  size_t node_count;
  size_t capacity;
  /* output->root is not necessarily table index 1: a comment or processing
     instruction before <html> is appended to the document's children first,
     so the html element lands later in preorder. root_index is resolved by
     pointer during the table build — never assumed — and is what
     output_root, materialize_output and (through Gumbo.Output.root/1)
     fragment_nodes treat as the root. It is GUMBO_NO_ROOT when the parse
     stopped before any element was built (stop_on_first_error can halt
     that early), which gumbo itself represents as output->root == NULL. */
  size_t root_index;
  /* Index arithmetic for the O(1) node accessors, filled once by
     gumbo_node_table_size: parent_indices[i] is the table index of
     nodes[i]'s parent (GUMBO_NO_PARENT for the document node) and
     subtree_sizes[i] the number of table entries in the subtree rooted at
     nodes[i]. Preorder makes every subtree a contiguous table range, so a
     sibling or child index is addition, never a pointer scan. */
  size_t* parent_indices;
  size_t* subtree_sizes;
} gumbo_handle_t;

/* Sentinel for parent_indices[i] when nodes[i] is the document node. */
#define GUMBO_NO_PARENT SIZE_MAX

/* Sentinel for root_index when the parse stopped before any element was
   built: output->root is NULL and the document has no children. */
#define GUMBO_NO_ROOT SIZE_MAX

/* Opens the resource type. Returns 0 on success; a nonzero return makes the
   NIF load fail. The type pointer is kept file-private; the NIF entry points
   in this file reach it through the helpers below. */
int gumbo_handle_init(ErlNifEnv* env);

/* enif_get_resource wrapper. Returns nonzero and sets *out on success;
   returns 0 when term is not a handle, in which case the caller answers
   {:error, :invalid_handle}. */
int gumbo_handle_get(ErlNifEnv* env, ERL_NIF_TERM term, gumbo_handle_t** out);

/* Node lookup status codes for gumbo_node_get. */
#define GUMBO_NODE_OK 0
#define GUMBO_NODE_INVALID_HANDLE 1
#define GUMBO_NODE_INVALID_NODE 2

/* Resolves (handle, index) to a node pointer with bounds checking. Returns
   GUMBO_NODE_OK on success, GUMBO_NODE_INVALID_HANDLE when the first term is
   not a handle, or GUMBO_NODE_INVALID_NODE when the index is not a node in
   that handle's table. On success *handle_out is the resolved handle too, so
   callers needing the parent/size arrays do not do a second resource lookup.
   The caller maps the failure codes to {:error, :invalid_handle} /
   {:error, :invalid_node}. */
int gumbo_node_get(ErlNifEnv* env, ERL_NIF_TERM handle_term,
                   ERL_NIF_TERM index_term, gumbo_handle_t** handle_out,
                   GumboNode** out);

/* The children vector per node type, or NULL for leaf types. */
GumboVector* gumbo_node_children(GumboNode* node);

/* parse(binary, options_map) -> {:ok, resource} | {:error, term}. */
ERL_NIF_TERM gumbo_nif_parse(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                             int argc, const ERL_NIF_TERM argv[]);

/* Gumbo.Output accessors, one per NIF. */
ERL_NIF_TERM gumbo_nif_output_document(ErlNifEnv* env,
                                       const gumbo_atoms_t* atoms, int argc,
                                       const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_output_root(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                   int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_output_input(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                                    int argc, const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_output_node_count(ErlNifEnv* env,
                                         const gumbo_atoms_t* atoms, int argc,
                                         const ERL_NIF_TERM argv[]);
ERL_NIF_TERM gumbo_nif_output_options(ErlNifEnv* env,
                                      const gumbo_atoms_t* atoms, int argc,
                                      const ERL_NIF_TERM argv[]);

#endif /* GUMBO_HANDLE_H_ */
