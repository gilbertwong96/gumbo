#!/usr/bin/env python3
"""Regenerates 0002-open-element-queries.patch against a pristine gumbo-parser.

Usage, from the repository root:

    python3 c_src/patches/gumbo-parser/0002-open-element-queries.py

It copies c_src/gumbo-parser/src to a scratch directory, applies the exact
substitutions below with an assertion per substitution (so a submodule bump that
moves any of this fails loudly here rather than producing a subtly different
patch), and rewrites the .patch next to this script with the timestamps stripped.

The alternative — hand-editing a copy and diffing — is how the first attempt at
0001 was made, and it shipped a patch whose hunk counts did not match. The script
is the recipe, and it is checked in so that rebasing onto a new pin is mechanical.
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "c_src" / "gumbo-parser" / "src"
SCRATCH = Path("/tmp/gumbo-patch-0002")
PATCH = Path(__file__).resolve().parent / "0002-open-element-queries.patch"

# The prose has to live with the patch: git apply drops commit messages, and the
# next person to rebase this onto a new pin needs to know what it is for and what
# can go wrong.
HEADER = """From: patched for this project, not from upstream
Subject: [PATCH 2/3] Answer the open-element queries in O(1) instead of walking the stack

Two queries over the parser's stack of open elements are asked once per tag and
answered by walking it, which makes the parse quadratic in nesting depth:
measured, `<div>`*20000 takes 274 ms and `<b>`*20000 takes 75 ms, and the
profiler puts 99.7% and 99% of that time in these two walks respectively.

  - has_an_element_in_button_scope(P), once per block-level start tag from
    maybe_implicitly_close_p_tag. It scans down to the nearest scope boundary,
    and a document nested with anything that is not a boundary has none, so it
    scans to the bottom every time. An open-p counter answers it without looking
    when no p is open at all, which is that document.

  - is_open_element(), once per formatting entry from
    reconstruct_active_formatting_elements and so once per tag. That one is a
    linear search of the whole stack for a pointer. A flag on the node answers it.

Both answers are exactly what the walks would have returned, so tree construction
is unchanged: the differential harness in c_src/test/parity_dump.c parses the same
seeded corpus with this build and with the pinned sources and compares the trees
node by node, and `make check-parity` runs it.

The thing that can go wrong is a mutation of the stack that does not say so, which
is why every mutation now goes through one of the five open_element_* functions
and none of them touches _open_elements directly. The asserts in those functions
catch a double push or a clear of a node that is not open, and they are live in
the harness because nothing defines NDEBUG there.

Upstream has no fix for this and neither does any engine: Blink, WebKit and Gecko
cap the tree depth at 512 and reparent instead, and Nokogiri's gumbo exposes
max_tree_depth (default 400). A depth cap would bound every walk at once, at the
price of refusing or reshaping the deep documents this library parses today. This
patch is the alternative that leaves tree construction alone.
---
"""


def sub(text: str, old: str, new: str, count: int = 1) -> str:
    found = text.count(old)
    if found != count:
        sys.exit(f"FAIL: expected {count} occurrence(s), found {found} of:\n{old[:400]}")
    return text.replace(old, new)


def main() -> int:
    subprocess.run(["rm", "-rf", str(SCRATCH)], check=True)
    SCRATCH.mkdir(parents=True)
    subprocess.run(["cp", "-R", str(SRC), str(SCRATCH / "src")], check=True)

    header = SCRATCH / "src" / "gumbo.h"
    parser = SCRATCH / "src" / "parser.c"

    # ---- gumbo.h: one flag on the node -------------------------------------
    text = header.read_text()
    text = sub(
        text,
        """  /**
   * A bitvector of flags containing information about why this element was
   * inserted into the parse tree, including a variety of special parse
   * situations.
   */
  GumboParseFlags parse_flags;
""",
        """  /**
   * A bitvector of flags containing information about why this element was
   * inserted into the parse tree, including a variety of special parse
   * situations.
   */
  GumboParseFlags parse_flags;

  /**
   * Internal to the tree builder: true while this node is in the parser's stack
   * of open elements. Kept here rather than answered by searching that stack,
   * because reconstruct_active_formatting_elements asks the question once per
   * formatting entry and so once per tag, and the stack is as deep as the
   * document is nested.
   */
  bool is_open;
""",
    )
    header.write_text(text)

    # ---- parser.c: the state, the flag's initial value, and the helpers ----
    text = parser.read_text()

    text = sub(
        text,
        "  node->parse_flags = GUMBO_INSERTION_NORMAL;\n  return node;",
        "  node->parse_flags = GUMBO_INSERTION_NORMAL;\n  node->is_open = false;\n  return node;",
    )

    # The state field, next to the stack it summarises.
    text = sub(
        text,
        """  GumboVector /*GumboNode*/ _open_elements;""",
        """  GumboVector /*GumboNode*/ _open_elements;
  /**
   * How many HTML <p> elements are in _open_elements. The button-scope query
   * starts by walking that stack from the top; when no p is open at all the
   * answer is false without looking, which is the case for every block-level
   * start tag in a document nested with tags that are not p, i.e. exactly the
   * shape that made the parse quadratic.
   */
  unsigned int _open_p_count;""",
    )

    text = sub(
        text,
        "  gumbo_vector_init(parser, 10, &parser_state->_open_elements);",
        "  gumbo_vector_init(parser, 10, &parser_state->_open_elements);\n  parser_state->_open_p_count = 0;",
    )

    # The five helpers, before their first caller (pop_current_node). Every
    # mutation of the stack goes through one of them.
    helpers = '''
/* The stack of open elements is what every scope query and every "is this node
   still open" question reads, and both used to be answered by walking it: the
   button-scope check scans to the bottom when the document has no scope boundary
   above, once per block-level start tag, and is_open_element searched the whole
   stack once per formatting entry and so once per tag. Keep the two answers
   instead. The only way to get them wrong is to mutate the stack without saying
   so, which is why every mutation goes through one of the five functions below
   and none of them calls gumbo_vector_* on _open_elements directly. */
static bool node_is_open_p(const GumboNode* node) {
  return node->type == GUMBO_NODE_ELEMENT &&
         node->v.element.tag == GUMBO_TAG_P &&
         node->v.element.tag_namespace == GUMBO_NAMESPACE_HTML;
}

static void open_element_clear(GumboParser* parser, GumboNode* node) {
  GumboParserState* state = parser->_parser_state;
  assert(node->is_open);
  node->is_open = false;
  if (node_is_open_p(node)) {
    assert(state->_open_p_count > 0);
    --state->_open_p_count;
  }
}

static void open_element_push(GumboParser* parser, GumboNode* node) {
  GumboParserState* state = parser->_parser_state;
  assert(!node->is_open);
  node->is_open = true;
  if (node_is_open_p(node)) {
    ++state->_open_p_count;
  }
  gumbo_vector_add(parser, (void*) node, &state->_open_elements);
}

static GumboNode* open_element_pop(GumboParser* parser) {
  GumboParserState* state = parser->_parser_state;
  GumboNode* node = (GumboNode*) gumbo_vector_pop(parser, &state->_open_elements);
  if (node != NULL) {
    open_element_clear(parser, node);
  }
  return node;
}

static void open_element_remove_at(GumboParser* parser, unsigned int index) {
  GumboParserState* state = parser->_parser_state;
  assert(index < state->_open_elements.length);
  open_element_clear(parser, (GumboNode*) state->_open_elements.data[index]);
  gumbo_vector_remove_at(parser, index, &state->_open_elements);
}

static void open_element_remove(GumboParser* parser, GumboNode* node) {
  GumboParserState* state = parser->_parser_state;
  /* The node is not always on the stack: the adoption agency algorithm removes
     elements it may already have taken out, and gumbo_vector_remove reports
     nothing about whether it removed anything, so ask where the node is first.
     This is the one place the patch still scans the stack, and it runs inside
     the adoption agency algorithm, which runs at most eight times per tag. */
  if (gumbo_vector_index_of(&state->_open_elements, node) < 0) {
    return;
  }
  open_element_clear(parser, node);
  gumbo_vector_remove(parser, node, &state->_open_elements);
}

static void open_element_insert_at(
    GumboParser* parser, GumboNode* node, unsigned int index) {
  GumboParserState* state = parser->_parser_state;
  assert(!node->is_open);
  node->is_open = true;
  if (node_is_open_p(node)) {
    ++state->_open_p_count;
  }
  gumbo_vector_insert_at(parser, node, index, &state->_open_elements);
}

static void open_element_replace_at(
    GumboParser* parser, unsigned int index, GumboNode* node) {
  GumboParserState* state = parser->_parser_state;
  GumboNode* previous = (GumboNode*) state->_open_elements.data[index];
  if (previous != node) {
    open_element_clear(parser, previous);
    assert(!node->is_open);
    node->is_open = true;
    if (node_is_open_p(node)) {
      ++state->_open_p_count;
    }
  }
  /* The tenth mutation site, and the one the first version of this patch missed:
     step 13.7 of the adoption agency algorithm swaps a clone in for the element
     it was cloned from, rather than pushing or removing. The assert in
     open_element_clear found it — the two answers were quietly wrong from then on,
     which changes what reconstruct_active_formatting_elements answers, which
     changes the tree. */
  state->_open_elements.data[index] = node;
}

static GumboNode* pop_current_node(GumboParser* parser) {'''
    text = sub(text, "\nstatic GumboNode* pop_current_node(GumboParser* parser) {", helpers)

    # clone_node copies the whole node, including the one field whose value must
    # not be inherited: the caller clones an element that is open, because that is
    # the adoption agency algorithm's whole subject. The differential harness
    # found this one, by asserting on a stale true that the struct copy had left
    # behind — with the assert compiled out it would have been silent.
    text = sub(
        text,
        """  *new_node = *node;
  new_node->parent = NULL;
  new_node->index_within_parent = -1;""",
        """  *new_node = *node;
  new_node->parent = NULL;
  new_node->index_within_parent = -1;
  /* The copy above carries is_open over too, and the node being cloned is open
     by definition here, so say plainly that the clone is not in the stack until
     something inserts it. A stale true would be silent: it only changes what
     reconstruct_active_formatting_elements answers, i.e. the shape of the tree. */
  new_node->is_open = false;""",
    )

    # ---- the mutations ----------------------------------------------------
    # The push in insert_element no longer names the stack, so its local state
    # pointer is dead; leave the warning-visible mess to nobody.
    text = sub(
        text,
        """static void insert_element(GumboParser* parser, GumboNode* node,
    bool is_reconstructing_formatting_elements) {
  GumboParserState* state = parser->_parser_state;
""",
        """static void insert_element(GumboParser* parser, GumboNode* node,
    bool is_reconstructing_formatting_elements) {
""",
    )
    text = sub(
        text,
        "  GumboNode* current_node = gumbo_vector_pop(parser, &state->_open_elements);",
        "  GumboNode* current_node = open_element_pop(parser);",
    )
    text = sub(
        text,
        """  InsertionLocation location = get_appropriate_insertion_location(parser, NULL);
  insert_node(parser, node, location);
  gumbo_vector_add(parser, (void*) node, &state->_open_elements);""",
        """  InsertionLocation location = get_appropriate_insertion_location(parser, NULL);
  insert_node(parser, node, location);
  open_element_push(parser, node);""",
    )
    text = sub(
        text,
        """    insert_node(parser, clone, location);
    gumbo_vector_add(
        parser, (void*) clone, &parser->_parser_state->_open_elements);""",
        """    insert_node(parser, clone, location);
    open_element_push(parser, clone);""",
    )
    text = sub(
        text,
        """      if (formatting_index == -1) {
        // Step 13.6.
        gumbo_vector_remove_at(parser, node_index, &state->_open_elements);
        continue;
      }""",
        """      if (formatting_index == -1) {
        // Step 13.6.
        open_element_remove_at(parser, node_index);
        continue;
      }""",
    )
    text = sub(
        text,
        """      assert(node_index >= 0);
      state->_open_elements.data[node_index] = node;""",
        """      assert(node_index >= 0);
      open_element_replace_at(parser, (unsigned int) node_index, node);""",
    )
    text = sub(
        text,
        """    // Step 19.
    gumbo_vector_remove(parser, formatting_node, &state->_open_elements);
    int insert_at =
        gumbo_vector_index_of(&state->_open_elements, furthest_block) + 1;
    assert(insert_at >= 0);
    assert((unsigned int) insert_at <= state->_open_elements.length);
    gumbo_vector_insert_at(
        parser, new_formatting_node, insert_at, &state->_open_elements);""",
        """    // Step 19.
    open_element_remove(parser, formatting_node);
    int insert_at =
        gumbo_vector_index_of(&state->_open_elements, furthest_block) + 1;
    assert(insert_at >= 0);
    assert((unsigned int) insert_at <= state->_open_elements.length);
    open_element_insert_at(parser, new_formatting_node, (unsigned int) insert_at);""",
    )
    text = sub(
        text,
        """    gumbo_vector_add(parser, state->_head_element, &state->_open_elements);
    bool result = handle_in_head(parser, token);
    gumbo_vector_remove(parser, state->_head_element, &state->_open_elements);""",
        """    open_element_push(parser, state->_head_element);
    bool result = handle_in_head(parser, token);
    open_element_remove(parser, state->_head_element);""",
    )
    text = sub(
        text,
        """        void* last_element = gumbo_vector_remove_at(
            parser, last_a, &state->_active_formatting_elements);
        gumbo_vector_remove(parser, last_element, &state->_open_elements);""",
        """        GumboNode* last_element = (GumboNode*) gumbo_vector_remove_at(
            parser, last_a, &state->_active_formatting_elements);
        open_element_remove(parser, last_element);""",
    )

    # ---- the queries ------------------------------------------------------
    text = sub(
        text,
        """static bool is_open_element(GumboParser* parser, const GumboNode* node) {
  GumboVector* open_elements = &parser->_parser_state->_open_elements;
  for (unsigned int i = 0; i < open_elements->length; ++i) {
    if (open_elements->data[i] == node) {
      return true;
    }
  }
  return false;
}""",
        """static bool is_open_element(GumboParser* parser, const GumboNode* node) {
  (void)parser;
  return node->is_open;
}""",
    )
    text = sub(
        text,
        """static bool maybe_implicitly_close_p_tag(
    GumboParser* parser, GumboToken* token) {
  if (has_an_element_in_button_scope(parser, GUMBO_TAG_P)) {""",
        """static bool has_open_p_in_button_scope(GumboParser* parser) {
  /* The counter is the fast path and the walk is the answer: with no p on the
     stack at all the walk would reach the bottom and return false, which is the
     common case in a deeply nested document. */
  return parser->_parser_state->_open_p_count != 0 &&
         has_an_element_in_button_scope(parser, GUMBO_TAG_P);
}

static bool maybe_implicitly_close_p_tag(
    GumboParser* parser, GumboToken* token) {
  if (has_open_p_in_button_scope(parser)) {""",
    )
    text = sub(
        text,
        """    if (!has_an_element_in_button_scope(parser, GUMBO_TAG_P)) {
      parser_add_parse_error(parser, token);""",
        """    if (!has_open_p_in_button_scope(parser)) {
      parser_add_parse_error(parser, token);""",
    )

    parser.write_text(text)

    # ---- the patch --------------------------------------------------------
    import difflib

    before = (SRC / "gumbo.h").read_text().splitlines(keepends=True)
    after = (SCRATCH / "src" / "gumbo.h").read_text().splitlines(keepends=True)
    header_diff = list(difflib.unified_diff(before, after, "a/src/gumbo.h", "b/src/gumbo.h"))
    before = (SRC / "parser.c").read_text().splitlines(keepends=True)
    after = (SCRATCH / "src" / "parser.c").read_text().splitlines(keepends=True)
    parser_diff = list(difflib.unified_diff(before, after, "a/src/parser.c", "b/src/parser.c"))

    body = "".join(header_diff) + "".join(parser_diff)
    body = re.sub(r"^(--- a/src/\S+)\t.*$", r"\1", body, flags=re.M)
    body = re.sub(r"^(\+\+\+ b/src/\S+)\t.*$", r"\1", body, flags=re.M)
    if not body.endswith("\n"):
        body += "\n"

    print(f"wrote {PATCH} ({body.count(chr(10))} lines)")
    PATCH.write_text(HEADER + body)
    return 0


if __name__ == "__main__":
    sys.exit(main())
