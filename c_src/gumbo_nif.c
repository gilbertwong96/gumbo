#include <string.h>

#include <erl_nif.h>

#include "gumbo.h"
#include "gumbo_atoms.h"
#include "gumbo_tags.h"

typedef struct {
  /* NIF-wide private state. Atom tables live here; resource types will
     follow in later tasks. */
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
    return enif_raise_exception(env, enif_make_atom(env, "allocation_failure"));
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
};

ERL_NIF_INIT(Elixir.Gumbo.Native, nif_funcs, gumbo_nif_load, NULL, NULL,
             gumbo_nif_unload)
