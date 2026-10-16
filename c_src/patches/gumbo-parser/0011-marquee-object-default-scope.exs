# The 0011 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0011-marquee-object-default-scope.patch.
# This one follows the current spec rather than the pin: the in-body end tag rule for
# `applet`, `marquee` and `object` asks for the element in scope, not in table scope.
#
# `priors` mirrors what the earlier generators did: 0011 edits text no earlier patch moves,
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
  Subject: [PATCH 11/11] Ask for applet, marquee and object in scope, not in table scope

  "In body", an end tag whose tag name is one of `applet`, `marquee`, `object` asks
  whether the stack of open elements has an element *in scope* with that tag name, and
  ignores the token if it does not. The pinned base asks `has_an_element_in_table_scope`,
  whose boundary set is only `html`, `table` and `template`.

  Table scope is a wider reach in a browser's stack than a select's: since `select` bounds
  a scope query (whatwg/html#10548, and 0007 here), an end tag written inside a select can
  no longer see an `applet`, `marquee` or `object` above it, and the spec ignores it. Asked
  in table scope, the select is no boundary at all, the element above is found, and the
  token pops the select and everything under it — which is the shape 439 `fuzz 181`
  reported: at `marquee > center > select` this library had child count 2 where Chrome had
  4, with the following `action-text-attachment` and text left outside the marquee.

  Chrome 155, on four witnesses, keeps the content where the spec does:

      <marquee><select></marquee><b>x              marquee(select(b("x")))
      <center><marquee><select></marquee><b>x      center(marquee(select(b("x"))))
      <marquee><select></center></marquee><b>x      marquee(select(b("x")))
      <marquee><textarea></textarea><center><select></center></marquee><b>x
                                                   marquee(textarea()center(select(b("x"))))

  and with the pin alone each of them ends the select at the end tag instead.

  This changes tree construction on purpose, so it sits outside the "pinned and patched
  trees are identical" claim `make check-parity` makes: the shapes it changes are held by
  `test/gumbo/select_scope_test.exs`, and the two-step form of that gate is what bounds it
  to documents whose tree holds a select.
  ---
  """,
  subs: [
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
                         (gumbo_tagset){TAG(APPLET), TAG(MARQUEE), TAG(OBJECT)})) {
            GumboTag token_tag = token->v.end_tag;
            if (!has_an_element_in_table_scope(parser, token_tag)) {
        """),
      to:
        t.(~S"""
                         (gumbo_tagset){TAG(APPLET), TAG(MARQUEE), TAG(OBJECT)})) {
            GumboTag token_tag = token->v.end_tag;
            if (!has_an_element_in_scope(parser, token_tag)) {
        """)
    }
  ]
}
