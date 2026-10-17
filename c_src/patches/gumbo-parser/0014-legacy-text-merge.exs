# The 0014 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0014-legacy-text-merge.patch. This one
# puts a foster-parented text run back in a node of its own, the way Nokogiri's fork does.
#
# `priors` is false: the function it edits, `maybe_flush_text_node_buffer`, is untouched by
# 0001-0013, so this is a deletion against the pinned text. That also makes it the opposite
# of 0013 in the one way the gates care about: it applies to the pin on its own, so it
# belongs in BEHAVIOUR_PATCHES, and the parity gate states its bound there with the rest.
#
# The layout is mix format's, not hand-kept: re-indenting a heredoc and its terminator
# together leaves the value alone, which is why this file lives in .formatter.exs.
#
# Files touched, in the order the substitutions run: parser.c

# The texts below are C, so they are written as heredocs and read as C. A heredoc's
# value ends with the newline before its terminator, which is exactly right for a text
# that ends with one; for the rest, `t/1` drops that single newline. No other shape
# occurs here, and `mix gumbo.patches --check` fails if a text is misrepresented.
t = &String.replace_suffix(&1, "\n", "")

%{
  priors: false,
  header: ~S"""
  From: patched for this project, not from upstream
  Subject: [PATCH 14/14] Insert foster parented text as its own node, for Nokogiri

  The reverse of upstream 41a0f3e ("spec: fix foster parented text not being merged into
  preceding text node", 2026-08-15), which made a flushed text run merge into whichever
  text node sits immediately before the adjusted insertion location. Nokogiri's fork of
  gumbo predates that change: `maybe_flush_text_node_buffer` there inserts the node as it
  stands, so a run foster parented out of a table stays a node of its own.

  Only on this branch, and only for a consumer that has to reproduce Nokogiri's trees.
  What it moves is text-node splitting, which rendering does not show — the port's stored
  corpus reads the same either way — but a tree comparison does, and so does anything
  acting per text node, an autolinker for instance. With 0013's mode this is the last
  difference between this branch's trees and the reference's whose mechanism is known: 21
  of the port's 1,058 bodies diverge by this alone, 2 of them on a scope path (a table
  inside an `option`), the rest reading as `other`, `unicode`, `template` or
  `bogus_comment` because that is where a structural comparison first lands.

  Unlike 0013 this is not cumulative and needs nothing outside the vendored copy: the
  function it edits is the pin's own text, so it applies to the pin on its own, joins
  BEHAVIOUR_PATCHES with 0007-0011, and the documents it moves are the ones whose tree
  holds a table, which is where a foster-parented run comes from. `make check-parity`'s
  pin-against-baseline step is what names that bound.

  The `assert` in the pinned function still holds: it is about the buffer, which this
  patch does not touch. What no longer holds is upstream's own test for it, in the pinned
  `tests/parser.cc`, which this project does not build.
  ---
  """,
  subs: [
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          InsertionLocation location = get_appropriate_insertion_location(parser, NULL);
          GumboNode* prev = NULL;
          if (location.target->type == GUMBO_NODE_ELEMENT ||
              location.target->type == GUMBO_NODE_TEMPLATE) {
            GumboVector* siblings = &location.target->v.element.children;
            if (location.index == -1) {
              if (siblings->length > 0) prev = siblings->data[siblings->length - 1];
            } else if (location.index > 0) {
              prev = siblings->data[location.index - 1];
            }
          }
          if (prev != NULL &&
              (prev->type == GUMBO_NODE_TEXT || prev->type == GUMBO_NODE_WHITESPACE) &&
              (text_node->type == GUMBO_NODE_TEXT ||
               text_node->type == GUMBO_NODE_WHITESPACE)) {
            GumboText* prev_data = &prev->v.text;
            size_t prev_length = strlen(prev_data->text);
            size_t added_length = strlen(text_node_data->text);
            char* merged = gumbo_parser_allocate(parser, prev_length + added_length + 1);
            memcpy(merged, prev_data->text, prev_length);
            memcpy(merged + prev_length, text_node_data->text, added_length + 1);
            gumbo_parser_deallocate(parser, (void*) prev_data->text);
            prev_data->text = merged;
            if (text_node->type == GUMBO_NODE_TEXT) {
              prev->type = GUMBO_NODE_TEXT;
            }
            destroy_node(parser, text_node);
          } else if (location.target->type == GUMBO_NODE_DOCUMENT) {
        """),
      to:
        t.(
          "  InsertionLocation location = get_appropriate_insertion_location(parser, NULL);\n  if (location.target->type == GUMBO_NODE_DOCUMENT) {\n"
        )
    }
  ]
}
