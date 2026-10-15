# The 0007 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0007-select-in-scope.patch. This one
# follows the current spec rather than the pin: whatwg/html#10548 removed the "in select"
# insertion mode and lists `select` among the "in scope" element types.
#
# `priors` mirrors what the earlier generators did: 0007 edits text no earlier patch moves,
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
  Subject: [PATCH 7/7] Put select among the scope types, as the relaxed select parser does

  WHATWG removed the "in select" insertion mode (whatwg/html#10548, merged 2025-07-22)
  and folded those rules into "in body", with `select` listed among the element types
  that bound a scope query. Gumbo never implemented the removed mode and its scope list
  predates the addition, so with the pin alone `</p>` inside a select finds the `p`
  *outside* it, closes that one, and lets the text after it escape as a sibling — a tree
  no version of the spec produces. Chrome inserts an empty `p` inside the select, closes
  that, and leaves the outer `p` and the text alone.

  This is the first patch here that changes tree construction on purpose, so it sits
  outside the "pinned and patched trees are identical" claim `make check-parity` makes:
  the shapes it changes are held by `test/gumbo/select_scope_test.exs` instead, and every
  document the parity corpus still generates parses identically.
  ---
  """,
  subs: [
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
        #define SCOPE_TAGS            \
          TAG(APPLET),                \
          TAG(CAPTION),               \
          TAG(HTML),                  \
          TAG(TABLE),                 \
          TAG(TD),                    \
          TAG(TH),                    \
          TAG(MARQUEE),               \
          TAG(OBJECT),                \
          TAG(TEMPLATE),              \
          TAG_MATHML(MI),             \
          TAG_MATHML(MO),             \
          TAG_MATHML(MN),             \
          TAG_MATHML(MS),             \
          TAG_MATHML(MTEXT),          \
          TAG_MATHML(ANNOTATION_XML), \
          TAG_SVG(FOREIGNOBJECT),     \
          TAG_SVG(DESC),              \
          TAG_SVG(TITLE)
        """),
      to:
        t.(~S"""
        #define SCOPE_TAGS            \
          TAG(APPLET),                \
          TAG(CAPTION),               \
          TAG(HTML),                  \
          TAG(TABLE),                 \
          TAG(TD),                    \
          TAG(TH),                    \
          TAG(MARQUEE),               \
          TAG(OBJECT),                \
          TAG(SELECT),                \
          TAG(TEMPLATE),              \
          TAG_MATHML(MI),             \
          TAG_MATHML(MO),             \
          TAG_MATHML(MN),             \
          TAG_MATHML(MS),             \
          TAG_MATHML(MTEXT),          \
          TAG_MATHML(ANNOTATION_XML), \
          TAG_SVG(FOREIGNOBJECT),     \
          TAG_SVG(DESC),              \
          TAG_SVG(TITLE)
        """)
    }
  ]
}
