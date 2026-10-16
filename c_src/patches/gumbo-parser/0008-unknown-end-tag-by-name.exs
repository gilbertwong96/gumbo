# The 0008 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0008-unknown-end-tag-by-name.patch.
# This one is not about a cost or a lever: it is a tree the reference builds and the
# pin does not, and it is old enough to predate every release still in use.
#
# `priors` mirrors what the earlier generators did: 0008 edits text no earlier patch moves,
# so it diffs against the pinned tree.
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
  Subject: [PATCH 8/8] Decide an unknown end tag by name, and leave a name it does not match alone

  In body, an end tag that matches no open element is handled by walking the stack of
  open elements: the walk stops at the element whose tag name equals the token's,
  closing up to and including it, and stops at the first element in the special
  category, ignoring the token. Custom elements are not in that category, so a name
  that matches nothing has to keep walking — and there the enum cannot answer the
  question, because every unknown tag is GUMBO_TAG_UNKNOWN.

  So `</fidiv>` matches an open `<f&#igure>`, closes it, and the text after it leaves
  the element:

      <div>a<f&#igure dchment="{nope">x</fidiv>/div>

  keeps `x/div>` in one text node inside the unknown element in the reference, and here
  writes two siblings, `x` and `/div>`. The input is what a chat application receives
  when a user pastes broken custom-element markup, which a corpus of 1058 documents
  produced 22 times.

  The names are compared when, and only when, the enum says unknown, so a known tag
  keeps the enum comparison and nothing about those paths moves. Foreign content has
  compared names this way — `gumbo_tag_from_original_text` and the ignore-case compare
  — since this file's first commit, because SVG case-normalisation needs it; this gives
  the in-body handler the same treatment, which is also what Nokogiri's vendored gumbo
  does, an internal fork of lua-gumbo's whose token carries the name where upstream's
  carries only the enum.

  Upstream has never compared names in this path: 0.14.1 does not, and its master still
  does not. Nor could its own gate ask for the change: of the 1019 tree-construction
  documents it runs, the four that carry two distinct unknown names at all are in SVG
  or MathML, which is the foreign path, the one that already compares names. So this
  patch is held by `test/gumbo/unknown_end_tag_test.exs` rather than by that corpus, and
  like 0007 it changes tree construction on purpose, which puts it outside the "pinned
  and patched trees are identical" claim: `make check-parity` applies this patch to its
  baseline along with 0007, and the documents its corpus holds are ones neither patch
  moves.
  ---
  """,
  subs: [
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
        static bool handle_any_other_end_tag(
        """),
      to:
        t.(~S"""
        // The walk below compares names the way the spec's does. A GumboTag cannot carry
        // a name — every unknown tag is GUMBO_TAG_UNKNOWN — so two different unknown names
        // compare equal on their own and the element one of them names is closed early.
        // Foreign content in this file has compared the text of the two tags since it was
        // written; this is the same comparison, for the handler that walks the open
        // elements of a document.
        static bool same_tag_name(const GumboNode* node, const GumboToken* token) {
          GumboStringPiece token_name = token->original_text;
          GumboStringPiece node_name = node->v.element.original_tag;
          gumbo_tag_from_original_text(&token_name);
          gumbo_tag_from_original_text(&node_name);
          if (token_name.length != node_name.length) {
            return false;
          }
          for (size_t i = 0; i < token_name.length; ++i) {
            char a = token_name.data[i];
            char b = node_name.data[i];
            if (a >= 'A' && a <= 'Z') {
              a += 'a' - 'A';
            }
            if (b >= 'A' && b <= 'Z') {
              b += 'a' - 'A';
            }
            if (a != b) {
              return false;
            }
          }
          return true;
        }

        static bool handle_any_other_end_tag(
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
            if (node_html_tag_is(node, end_tag)) {
        """),
      to:
        t.(~S"""
            if (node_html_tag_is(node, end_tag) &&
                (end_tag != GUMBO_TAG_UNKNOWN || same_tag_name(node, token))) {
        """)
    }
  ]
}
