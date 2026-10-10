#include <string.h>

#include <erl_nif.h>

#include "gumbo.h"

typedef struct {
  /* NIF-wide private state. Atom tables and resource types live here;
     smoke/0 needs no state yet. */
  int _reserved;
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

static int gumbo_nif_load(ErlNifEnv* env, void** priv_data,
                          ERL_NIF_TERM load_info) {
  (void)env;
  (void)load_info;

  gumbo_nif_priv_t* priv = enif_alloc(sizeof(gumbo_nif_priv_t));
  if (priv == NULL) {
    return 1;
  }
  priv->_reserved = 0;
  *priv_data = priv;
  return 0;
}

static void gumbo_nif_unload(ErlNifEnv* env, void* priv_data) {
  (void)env;
  enif_free(priv_data);
}

static ErlNifFunc nif_funcs[] = {
    {"smoke", 0, nif_smoke, 0},
};

ERL_NIF_INIT(Elixir.Gumbo.Native, nif_funcs, gumbo_nif_load, NULL, NULL,
             gumbo_nif_unload)
