#include <erl_nif.h>
#include <string.h>

#include "gumbo.h"
#include "gumbo_atoms.h"
#include "gumbo_attr.h"
#include "gumbo_error.h"
#include "gumbo_handle.h"
#include "gumbo_materialize.h"
#include "gumbo_node.h"
#include "gumbo_tags.h"

typedef struct {
  /* NIF-wide private state. The atom tables live here; the parse resource
     type is file-private in gumbo_handle.c behind gumbo_handle_init. */
  gumbo_atoms_t atoms;
} gumbo_nif_priv_t;

static ERL_NIF_TERM nif_smoke(ErlNifEnv* env, int argc,
                              const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;

  const char* name = gumbo_normalized_tagname(GUMBO_TAG_DIV);
  size_t len = strlen(name);

  ErlNifBinary bin;
  if (!enif_alloc_binary(len, &bin)) {
    return enif_make_badarg(env);
  }
  memcpy(bin.data, name, len);

  return enif_make_binary(env, &bin);
}

static ERL_NIF_TERM nif_tag_name(ErlNifEnv* env, int argc,
                                 const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_tag_name(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_tag_from_name(ErlNifEnv* env, int argc,
                                      const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_tag_from_name(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_tag_void(ErlNifEnv* env, int argc,
                                 const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_tag_void(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_tag_svg_name(ErlNifEnv* env, int argc,
                                     const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_tag_svg_name(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_tag_from_original_text(ErlNifEnv* env, int argc,
                                               const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_tag_from_original_text(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_tag_all(ErlNifEnv* env, int argc,
                                const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_tag_all(env, &priv->atoms, argc, argv);
}

/* Parse and materialize are registered twice against the same body, once
   plain and once with ERL_NIF_DIRTY_JOB_CPU_BOUND. The normal wrappers call
   enif_consume_timeslice: on a normal scheduler the hint is meaningful —
   these NIFs are one blocking call with no inner loop to hint from, so the
   hint announces the whole timeslice up front. The dirty wrappers do not
   call it: on a dirty scheduler the accounting is meaningless and would
   report the wrong thing, so the split is by entry point, not a runtime
   branch on the thread type. */
static ERL_NIF_TERM nif_parse_normal(ErlNifEnv* env, int argc,
                                     const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  enif_consume_timeslice(env, 100);
  return gumbo_nif_parse(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_parse_dirty(ErlNifEnv* env, int argc,
                                    const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_parse(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_output_document(ErlNifEnv* env, int argc,
                                        const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_output_document(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_output_root(ErlNifEnv* env, int argc,
                                    const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_output_root(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_output_input(ErlNifEnv* env, int argc,
                                     const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_output_input(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_output_node_count(ErlNifEnv* env, int argc,
                                          const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_output_node_count(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_output_options(ErlNifEnv* env, int argc,
                                       const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_output_options(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_node_details(ErlNifEnv* env, int argc,
                                     const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_node_details(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_node_children(ErlNifEnv* env, int argc,
                                      const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_node_children(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_node_parent(ErlNifEnv* env, int argc,
                                    const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_node_parent(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_node_next(ErlNifEnv* env, int argc,
                                  const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_node_next(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_node_previous(ErlNifEnv* env, int argc,
                                      const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_node_previous(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_node_attributes(ErlNifEnv* env, int argc,
                                        const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_node_attributes(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_node_attribute(ErlNifEnv* env, int argc,
                                       const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_node_attribute(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_attr_details(ErlNifEnv* env, int argc,
                                     const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_attr_details(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_output_errors(ErlNifEnv* env, int argc,
                                      const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_output_errors(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_error_fields(ErlNifEnv* env, int argc,
                                     const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_error_fields(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_error_message(ErlNifEnv* env, int argc,
                                      const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_error_message(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_error_caret(ErlNifEnv* env, int argc,
                                    const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_error_caret(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_materialize_output_normal(ErlNifEnv* env, int argc,
                                                  const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  enif_consume_timeslice(env, 100);
  return gumbo_nif_materialize_output(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_materialize_output_dirty(ErlNifEnv* env, int argc,
                                                 const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_materialize_output(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_materialize_node_normal(ErlNifEnv* env, int argc,
                                                const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  enif_consume_timeslice(env, 100);
  return gumbo_nif_materialize_node(env, &priv->atoms, argc, argv);
}

static ERL_NIF_TERM nif_materialize_node_dirty(ErlNifEnv* env, int argc,
                                               const ERL_NIF_TERM argv[]) {
  gumbo_nif_priv_t* priv = enif_priv_data(env);
  return gumbo_nif_materialize_node(env, &priv->atoms, argc, argv);
}

static int gumbo_nif_load(ErlNifEnv* env, void** priv_data,
                          ERL_NIF_TERM load_info) {
  (void)load_info;

  gumbo_nif_priv_t* priv = enif_alloc(sizeof(gumbo_nif_priv_t));
  if (priv == NULL) {
    return 1;
  }
  if (gumbo_atoms_init(env, &priv->atoms) != 0) {
    enif_free(priv);
    return 1;
  }
  if (gumbo_handle_init(env) != 0) {
    enif_free(priv);
    return 1;
  }
  *priv_data = priv;
  return 0;
}

static void gumbo_nif_unload(ErlNifEnv* env, void* priv_data) {
  (void)env;
  enif_free(priv_data);
}

static ErlNifFunc nif_funcs[] = {
    {"smoke", 0, nif_smoke, 0},
    {"tag_name", 1, nif_tag_name, 0},
    {"tag_from_name", 1, nif_tag_from_name, 0},
    {"tag_void", 1, nif_tag_void, 0},
    {"tag_svg_name", 1, nif_tag_svg_name, 0},
    {"tag_from_original_text", 1, nif_tag_from_original_text, 0},
    {"tag_all", 0, nif_tag_all, 0},
    {"parse", 2, nif_parse_normal, 0},
    {"parse_dirty", 2, nif_parse_dirty, ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"output_document", 1, nif_output_document, 0},
    {"output_root", 1, nif_output_root, 0},
    {"output_input", 1, nif_output_input, 0},
    {"output_node_count", 1, nif_output_node_count, 0},
    {"output_options", 1, nif_output_options, 0},
    {"node_details", 2, nif_node_details, 0},
    {"node_children", 2, nif_node_children, 0},
    {"node_parent", 2, nif_node_parent, 0},
    {"node_next", 2, nif_node_next, 0},
    {"node_previous", 2, nif_node_previous, 0},
    {"node_attributes", 2, nif_node_attributes, 0},
    {"node_attribute", 3, nif_node_attribute, 0},
    {"attr_details", 3, nif_attr_details, 0},
    {"output_errors", 1, nif_output_errors, 0},
    {"error_fields", 2, nif_error_fields, 0},
    {"error_message", 2, nif_error_message, 0},
    {"error_caret", 2, nif_error_caret, 0},
    {"materialize_output", 2, nif_materialize_output_normal, 0},
    {"materialize_output_dirty", 2, nif_materialize_output_dirty,
     ERL_NIF_DIRTY_JOB_CPU_BOUND},
    {"materialize_node", 3, nif_materialize_node_normal, 0},
    {"materialize_node_dirty", 3, nif_materialize_node_dirty,
     ERL_NIF_DIRTY_JOB_CPU_BOUND},
};

ERL_NIF_INIT(Elixir.Gumbo.Native, nif_funcs, gumbo_nif_load, NULL, NULL,
             gumbo_nif_unload)
