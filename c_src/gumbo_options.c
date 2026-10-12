#include "gumbo_options.h"

#include <limits.h> /* UINT_MAX, the "no cap" value our -1 maps to */

/* The tag-atom scan covers the interned table (154 real tags plus
   :unknown); GUMBO_TAG_LAST itself is not in the table because it is the
   "no fragment" marker, represented by nil. */
static int gumbo_decode_tag(const gumbo_atoms_t* atoms, ERL_NIF_TERM value,
                            GumboTag* out) {
  int i;
  for (i = 0; i < GUMBO_TAG_COUNT; ++i) {
    if (enif_is_identical(value, atoms->tags[i])) {
      *out = (GumboTag)i;
      return 1;
    }
  }
  return 0;
}

static int gumbo_decode_dirty(const gumbo_atoms_t* atoms, ERL_NIF_TERM value,
                              gumbo_dirty_t* out) {
  if (enif_is_identical(value, atoms->auto_)) {
    *out = GUMBO_DIRTY_AUTO;
    return 1;
  }
  if (enif_is_identical(value, atoms->true_)) {
    *out = GUMBO_DIRTY_FORCE;
    return 1;
  }
  if (enif_is_identical(value, atoms->false_)) {
    *out = GUMBO_DIRTY_NORMAL;
    return 1;
  }
  return 0;
}

int gumbo_options_decode(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                         ERL_NIF_TERM options_map, gumbo_handle_t* h) {
  ERL_NIF_TERM value;

  h->options = kGumboDefaultOptions;
  h->dirty = GUMBO_DIRTY_AUTO;

  if (!enif_get_map_value(env, options_map, atoms->tab_stop, &value)) {
    return 0;
  }
  if (!enif_get_int(env, value, &h->options.tab_stop) ||
      h->options.tab_stop < 1) {
    return 0;
  }

  if (!enif_get_map_value(env, options_map, atoms->stop_on_first_error,
                          &value)) {
    return 0;
  }
  if (enif_is_identical(value, atoms->true_)) {
    h->options.stop_on_first_error = true;
  } else if (enif_is_identical(value, atoms->false_)) {
    h->options.stop_on_first_error = false;
  } else {
    return 0;
  }

  if (!enif_get_map_value(env, options_map, atoms->max_errors, &value)) {
    return 0;
  }
  if (!enif_get_int(env, value, &h->options.max_errors) ||
      h->options.max_errors < -1) {
    return 0;
  }

  /* Our -1 means no cap, gumbo's field is unsigned where UINT_MAX means the
     same thing. Anything above C int range cannot be encoded back for
     options/1, so it is rejected before it gets here. */
  if (!enif_get_map_value(env, options_map, atoms->max_attributes, &value)) {
    return 0;
  }
  int max_attributes;
  if (!enif_get_int(env, value, &max_attributes) || max_attributes < -1) {
    return 0;
  }
  h->options.max_attributes =
      (max_attributes < 0) ? UINT_MAX : (unsigned int)max_attributes;

  if (!enif_get_map_value(env, options_map, atoms->fragment_context, &value)) {
    return 0;
  }
  if (enif_is_identical(value, atoms->nil)) {
    h->options.fragment_context = GUMBO_TAG_LAST;
  } else if (!gumbo_decode_tag(atoms, value, &h->options.fragment_context)) {
    return 0;
  }

  if (!enif_get_map_value(env, options_map, atoms->fragment_namespace,
                          &value)) {
    return 0;
  }
  if (enif_is_identical(value, atoms->namespaces[GUMBO_NAMESPACE_HTML])) {
    h->options.fragment_namespace = GUMBO_NAMESPACE_HTML;
  } else if (enif_is_identical(value, atoms->namespaces[GUMBO_NAMESPACE_SVG])) {
    h->options.fragment_namespace = GUMBO_NAMESPACE_SVG;
  } else if (enif_is_identical(value,
                               atoms->namespaces[GUMBO_NAMESPACE_MATHML])) {
    h->options.fragment_namespace = GUMBO_NAMESPACE_MATHML;
  } else {
    return 0;
  }

  if (!enif_get_map_value(env, options_map, atoms->dirty, &value)) {
    return 0;
  }
  if (!gumbo_decode_dirty(atoms, value, &h->dirty)) {
    return 0;
  }

  return 1;
}

static ERL_NIF_TERM gumbo_dirty_atom(const gumbo_atoms_t* atoms,
                                     gumbo_dirty_t dirty) {
  switch (dirty) {
    case GUMBO_DIRTY_FORCE:
      return atoms->true_;
    case GUMBO_DIRTY_NORMAL:
      return atoms->false_;
    default:
      return atoms->auto_;
  }
}

int gumbo_options_encode(ErlNifEnv* env, const gumbo_atoms_t* atoms,
                         const gumbo_handle_t* h, ERL_NIF_TERM* out) {
  ERL_NIF_TERM keys[7];
  ERL_NIF_TERM values[7];

  keys[0] = atoms->tab_stop;
  values[0] = enif_make_int(env, h->options.tab_stop);
  keys[1] = atoms->stop_on_first_error;
  values[1] = h->options.stop_on_first_error ? atoms->true_ : atoms->false_;
  keys[2] = atoms->max_errors;
  values[2] = enif_make_int(env, h->options.max_errors);
  keys[3] = atoms->fragment_context;
  values[3] = (h->options.fragment_context == GUMBO_TAG_LAST)
                  ? atoms->nil
                  : atoms->tags[h->options.fragment_context];
  keys[4] = atoms->fragment_namespace;
  values[4] = atoms->namespaces[h->options.fragment_namespace];
  keys[5] = atoms->dirty;
  values[5] = gumbo_dirty_atom(atoms, h->dirty);
  keys[6] = atoms->max_attributes;
  values[6] = enif_make_int(env, (h->options.max_attributes == UINT_MAX)
                                     ? -1
                                     : (int)h->options.max_attributes);

  return enif_make_map_from_arrays(env, keys, values, 7, out);
}
