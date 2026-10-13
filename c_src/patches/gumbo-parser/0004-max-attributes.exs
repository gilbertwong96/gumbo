# The 0004 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0004-max-attributes.patch. Ported one to one
# from the Python generator when that tooling was replaced, so the header below is the
# same prose and the substitutions are the same ones.
#
# `priors` mirrors what that generator did: 0004 was written before the earlier patches existed, so it diffs against the pinned tree.
#
# Files touched, in the order the substitutions run: gumbo.h, parser.c, tokenizer.c

# The texts below are C, so they are written as heredocs and read as C. A heredoc's
# value ends with the newline before its terminator, which is exactly right for a text
# that ends with one; for the rest, `t/1` drops that single newline. No other shape
# occurs here, and `mix gumbo.patches --check` fails if a text is misrepresented.
t = &String.replace_suffix(&1, "\n", "")

%{
  priors: false,
  header: ~S"""
From: patched for this project, not from upstream
Subject: [PATCH 4/4] Index attribute names, and cap how many one element may carry

Two things about attributes, both measured on a 16 MiB input:

  * Deciding whether an attribute name has already been seen was a scan of every
    attribute collected so far (strlen plus memcmp per candidate), so one element
    with n distinct names cost n^2 comparisons: 80 000 of them from 0.7 MB of input
    took 13.6 seconds, and the input cap allows about 2.4 million. Names are indexed
    now, by a per-tag FNV-1a hash into a bucket array that doubles as the attributes
    outnumber the buckets, so a lookup walks a chain of about one and a collision
    costs a comparison rather than a scan. The seed comes from the bucket array's
    address, so a crafted set of names cannot be made to collide on purpose, and a
    bucket hit is always confirmed with the full comparison, so a collision can only
    cost time.

  * There was no ceiling at all on how many attributes one element could carry.
    GumboOptions.max_attributes now sets one, 1024 by default, and attributes beyond
    it are dropped and GumboOutput.too_many_attributes is set. The cap is what makes
    the answer to "how bad can this get" a number rather than a limit, and it is the
    same lever Nokogiri's gumbo exposes under the same name.

The hash is what makes the cost linear whether or not the cap is set; the cap is
what tells a caller their document was too much for the parse they asked for. Neither
changes what the parser builds for a document inside the cap, which is what
`make check-parity` asserts — its corpus now generates elements with dozens of
attributes, distinct and repeated, precisely so that a mistake here shows up as a
tree difference rather than as a hang nobody tests.
---
""",
  subs: [
    %{
      file: "gumbo.h",
      count: 1,
      from: t.(~S"""
  GumboNamespaceEnum fragment_namespace;
} GumboOptions;
"""),
      to: t.(~S"""
  GumboNamespaceEnum fragment_namespace;

  /**
   * The largest number of attributes one element may carry. Attributes beyond it
   * are dropped rather than added, and GumboOutput.too_many_attributes is set so
   * that the caller can tell. UINT_MAX (or the -1 this library passes for it)
   * means no limit; the default is 1024. Nothing else about the parse changes,
   * and an element well inside the limit is unaffected.
   */
  unsigned int max_attributes;
} GumboOptions;
""")
    },
    %{
      file: "gumbo.h",
      count: 1,
      from: t.(~S"""
  GumboVector /* GumboError */ errors;
} GumboOutput;
"""),
      to: t.(~S"""
  GumboVector /* GumboError */ errors;

  /**
   * True if any attribute was dropped because its element reached
   * GumboOptions.max_attributes. The parse still succeeds and the tree is still the
   * best-effort one; this says the tree is missing something the parser was told not
   * to keep.
   */
  bool too_many_attributes;
} GumboOutput;
""")
    },
    %{
      file: "parser.c",
      count: 1,
      from: t.(~S"""
const GumboOptions kGumboDefaultOptions = {&malloc_wrapper, &free_wrapper, NULL,
    8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML};
"""),
      to: t.(~S"""
const GumboOptions kGumboDefaultOptions = {&malloc_wrapper, &free_wrapper, NULL,
    8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML, 1024};
""")
    },
    %{
      file: "parser.c",
      count: 1,
      from: t.(~S"""
static void output_init(GumboParser* parser) {
  GumboOutput* output = gumbo_parser_allocate(parser, sizeof(GumboOutput));
  output->root = NULL;
"""),
      to: t.(~S"""
static void output_init(GumboParser* parser) {
  GumboOutput* output = gumbo_parser_allocate(parser, sizeof(GumboOutput));
  output->root = NULL;
  output->too_many_attributes = false;
""")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from: t.(~S"""
  GumboVector /* GumboAttribute */ _attributes;
"""),
      to: t.(~S"""
  GumboVector /* GumboAttribute */ _attributes;

  // Buckets over the attribute names collected for the current tag, so that
  // deciding whether a name has already been seen is not a scan of every attribute
  // collected so far: without them one element's attributes cost the square of
  // their count, and 80 000 distinct names from 0.7 MB of input measured 13.6
  // seconds. _attribute_buckets holds indices + 1 (0 = empty) and is always a power
  // of two; _attribute_next holds one chain link per attribute, in the same order as
  // _attributes. The seed comes from the bucket array's address, so a crafted set of
  // names cannot be made to collide on purpose.
  GumboVector /* unsigned int */ _attribute_buckets;
  GumboVector /* unsigned int */ _attribute_next;
  unsigned int _attribute_hash_seed;
""")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from: t.(~S"""
static void mark_tag_state_as_empty(GumboTagState* tag_state) {
"""),
      to: t.(~S"""
#define kAttributeBucketsInitial 16

// FNV-1a over the name bytes, seeded per tag. Collisions cost an extra comparison,
// never correctness: every bucket hit is confirmed with the full name comparison.
static unsigned int hash_attribute_name(
    unsigned int seed, const char* data, size_t length) {
  unsigned int hash = seed ^ 2166136261u;
  for (size_t i = 0; i < length; ++i) {
    hash ^= (unsigned char) data[i];
    hash *= 16777619u;
  }
  return hash;
}

static unsigned int attribute_bucket_index(
    const GumboTagState* tag_state, unsigned int hash) {
  return hash & (unsigned int) (tag_state->_attribute_buckets.length - 1);
}

// Frees the index; the attribute vector itself is either transferred to the token or
// freed by the caller. Zeroing here rather than relying on mark_tag_state_as_empty,
// which is compiled out without NDEBUG, is what lets start_tag_state assert on it.
static void release_tag_attribute_index(
    GumboParser* parser, GumboTagState* tag_state) {
  gumbo_parser_deallocate(parser, tag_state->_attribute_buckets.data);
  tag_state->_attribute_buckets.data = NULL;
  tag_state->_attribute_buckets.length = 0;
  tag_state->_attribute_buckets.capacity = 0;
  gumbo_parser_deallocate(parser, tag_state->_attribute_next.data);
  tag_state->_attribute_next.data = NULL;
  tag_state->_attribute_next.length = 0;
  tag_state->_attribute_next.capacity = 0;
}

// Doubles the buckets and relinks every attribute collected so far, which is what
// keeps the chains about one long. Called after an insert, so it rebuilds the chain
// the insert just made along with all the others.
static void grow_attribute_buckets(GumboParser* parser, GumboTagState* tag_state) {
  size_t new_length = tag_state->_attribute_buckets.length * 2;
  void** grown = gumbo_parser_allocate(parser, sizeof(void*) * new_length);
  memset(grown, 0, sizeof(void*) * new_length);
  gumbo_parser_deallocate(parser, tag_state->_attribute_buckets.data);
  tag_state->_attribute_buckets.data = grown;
  tag_state->_attribute_buckets.length = new_length;
  tag_state->_attribute_buckets.capacity = new_length;

  GumboVector* /* GumboAttribute* */ attributes = &tag_state->_attributes;
  for (unsigned int i = 0; i < attributes->length; ++i) {
    const GumboAttribute* attr = attributes->data[i];
    unsigned int hash = hash_attribute_name(tag_state->_attribute_hash_seed,
        attr->name, strlen(attr->name));
    unsigned int bucket = attribute_bucket_index(tag_state, hash);
    tag_state->_attribute_next.data[i] = tag_state->_attribute_buckets.data[bucket];
    tag_state->_attribute_buckets.data[bucket] = (void*) (uintptr_t) (i + 1);
  }
}

static void mark_tag_state_as_empty(GumboTagState* tag_state) {
""")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from: t.(~S"""
  tokenizer->_tag_state._last_start_tag = GUMBO_TAG_LAST;
"""),
      to: t.(~S"""
  tokenizer->_tag_state._last_start_tag = GUMBO_TAG_LAST;
  tokenizer->_tag_state._attribute_buckets.data = NULL;
  tokenizer->_tag_state._attribute_buckets.length = 0;
  tokenizer->_tag_state._attribute_buckets.capacity = 0;
  tokenizer->_tag_state._attribute_next.data = NULL;
  tokenizer->_tag_state._attribute_next.length = 0;
  tokenizer->_tag_state._attribute_next.capacity = 0;
  tokenizer->_tag_state._attribute_hash_seed = 0;
""")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from: t.(~S"""
    output->v.start_tag.is_self_closing = tag_state->_is_self_closing;
    tag_state->_last_start_tag = tag_state->_tag;
    mark_tag_state_as_empty(tag_state);
"""),
      to: t.(~S"""
    output->v.start_tag.is_self_closing = tag_state->_is_self_closing;
    tag_state->_last_start_tag = tag_state->_tag;
    release_tag_attribute_index(parser, tag_state);
    mark_tag_state_as_empty(tag_state);
""")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from: t.(~S"""
    gumbo_parser_deallocate(parser, tag_state->_attributes.data);
    mark_tag_state_as_empty(tag_state);
    gumbo_debug(
        "Emitted end tag %s.\n", gumbo_normalized_tagname(tag_state->_tag));
"""),
      to: t.(~S"""
    gumbo_parser_deallocate(parser, tag_state->_attributes.data);
    release_tag_attribute_index(parser, tag_state);
    mark_tag_state_as_empty(tag_state);
    gumbo_debug(
        "Emitted end tag %s.\n", gumbo_normalized_tagname(tag_state->_tag));
""")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from: t.(~S"""
  gumbo_parser_deallocate(parser, tag_state->_attributes.data);
  mark_tag_state_as_empty(tag_state);
  gumbo_string_buffer_destroy(parser, &tag_state->_buffer);
  gumbo_debug("Abandoning current tag.\n");
"""),
      to: t.(~S"""
  gumbo_parser_deallocate(parser, tag_state->_attributes.data);
  release_tag_attribute_index(parser, tag_state);
  mark_tag_state_as_empty(tag_state);
  gumbo_string_buffer_destroy(parser, &tag_state->_buffer);
  gumbo_debug("Abandoning current tag.\n");
""")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from: t.(~S"""
  assert(tag_state->_attributes.data == NULL);
"""),
      to: t.(~S"""
  assert(tag_state->_attributes.data == NULL);
  assert(tag_state->_attribute_buckets.data == NULL);
  assert(tag_state->_attribute_next.data == NULL);
""")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from: t.(~S"""
  gumbo_vector_init(parser, 1, &tag_state->_attributes);
  tag_state->_drop_next_attr_value = false;
"""),
      to: t.(~S"""
  gumbo_vector_init(parser, 1, &tag_state->_attributes);
  gumbo_vector_init(parser, kAttributeBucketsInitial, &tag_state->_attribute_buckets);
  tag_state->_attribute_buckets.length = kAttributeBucketsInitial;
  memset(tag_state->_attribute_buckets.data, 0,
      sizeof(void*) * kAttributeBucketsInitial);
  tag_state->_attribute_next.data = NULL;
  tag_state->_attribute_next.length = 0;
  tag_state->_attribute_next.capacity = 0;
  tag_state->_attribute_hash_seed =
      (unsigned int) (uintptr_t) tag_state->_attribute_buckets.data;
  tag_state->_drop_next_attr_value = false;
""")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from: t.(~S"""
  GumboVector* /* GumboAttribute* */ attributes = &tag_state->_attributes;
  for (unsigned int i = 0; i < attributes->length; ++i) {
    GumboAttribute* attr = attributes->data[i];
    if (strlen(attr->name) == tag_state->_buffer.length &&
        memcmp(attr->name, tag_state->_buffer.data,
            tag_state->_buffer.length) == 0) {
      // Identical attribute; bail.
      add_duplicate_attr_error(parser, attr->name, i, attributes->length);
      tag_state->_drop_next_attr_value = true;
      return false;
    }
  }

  GumboAttribute* attr = gumbo_parser_allocate(parser, sizeof(GumboAttribute));
"""),
      to: t.(~S"""
  GumboVector* /* GumboAttribute* */ attributes = &tag_state->_attributes;
  unsigned int hash = hash_attribute_name(tag_state->_attribute_hash_seed,
      tag_state->_buffer.data, tag_state->_buffer.length);
  unsigned int bucket = attribute_bucket_index(tag_state, hash);
  unsigned int link =
      (unsigned int) (uintptr_t) tag_state->_attribute_buckets.data[bucket];
  while (link != 0) {
    unsigned int i = link - 1;
    GumboAttribute* attr = attributes->data[i];
    if (strlen(attr->name) == tag_state->_buffer.length &&
        memcmp(attr->name, tag_state->_buffer.data,
            tag_state->_buffer.length) == 0) {
      // Identical attribute; bail.
      add_duplicate_attr_error(parser, attr->name, i, attributes->length);
      tag_state->_drop_next_attr_value = true;
      return false;
    }
    link = (unsigned int) (uintptr_t) tag_state->_attribute_next.data[i];
  }

  if (attributes->length >= parser->_options->max_attributes) {
    // Dropped, and reported through the output rather than through an error: the
    // attributes were not wrong, there were simply more than the caller allowed. The
    // value that follows belongs to an attribute that was never added, so drop it the
    // way a duplicate does.
    parser->_output->too_many_attributes = true;
    tag_state->_drop_next_attr_value = true;
    reinitialize_tag_buffer(parser);
    return false;
  }

  GumboAttribute* attr = gumbo_parser_allocate(parser, sizeof(GumboAttribute));
""")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from: t.(~S"""
  gumbo_vector_add(parser, attr, attributes);
  reinitialize_tag_buffer(parser);
"""),
      to: t.(~S"""
  gumbo_vector_add(parser, attr, attributes);
  gumbo_vector_add(parser, tag_state->_attribute_buckets.data[bucket],
      &tag_state->_attribute_next);
  tag_state->_attribute_buckets.data[bucket] =
      (void*) (uintptr_t) attributes->length;
  if (attributes->length > tag_state->_attribute_buckets.length / 2) {
    grow_attribute_buckets(parser, tag_state);
  }
  reinitialize_tag_buffer(parser);
""")
    },
  ]
}
