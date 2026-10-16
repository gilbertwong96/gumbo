# The 0010 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0010-select-is-special.patch. This one
# follows the current spec rather than the pin: the "special" category lists `select`.
#
# `priors` mirrors what the earlier generators did: 0010 edits text no earlier patch moves,
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
  Subject: [PATCH 10/10] Put select in the special category, which is where an end tag's walk stops

  The spec's "special" category has named `select` for a long time: WebKit's bug 44390
  quoted the list in 2010 with `select` between `section` and `style`, and the current
  standard still names it, between `section` and `source`. The pinned base's
  `is_special_node` is a stale copy of that list — it jumps from SECTION to STYLE — and
  Nokogiri's fork has SELECT, so this is a list where the two forks differ in that
  direction. It is not a rule the standard gained recently.

  `is_special_node` is what three spec clauses read: the `<li>`/`<dd>`/`<dt>` start tag
  loop, the "any other end tag" walk, and the adoption agency's furthest block. An end tag
  with no matching open element walks up the stack of open elements and stops either at a
  matching tag name or at an element in the special category, where it reports a parse
  error and ignores the token. Without `select` in that list, `</option>` inside an open
  `<select>` walks past the select, reaches the option above it, and pops both, so whatever
  the document writes after that end tag escapes the select:

      <option><select>x</option>y     this tree: body > [option > select > ["x"], "y"]
      Chrome 155, same bytes:         body > option > select > ["xy"]

  The spec's category also lists `main`, `search`, `keygen`, `source` and `track`, which
  both forks lack. They are left alone: this patch is the one the reported shapes need, and
  each of the others would move documents that nothing here measures.

  This changes tree construction on purpose, so it sits outside the "pinned and patched
  trees are identical" claim `make check-parity` makes: the shapes it changes are held by
  `test/gumbo/special_category_test.exs` instead, and the two-step form of that gate is
  what bounds it to documents whose tree holds a select.
  ---
  """,
  subs: [
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
                  TAG(SECTION),
                  TAG(STYLE),
        """),
      to:
        t.(~S"""
                  TAG(SECTION),
                  TAG(SELECT),
                  TAG(STYLE),
        """)
    }
  ]
}
