# The 0012 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0012-in-table-text-current-node.patch.
#
# `priors` is false: `handle_in_table` is untouched by 0001-0011, so this is the pinned
# text with one condition added. `make check-parity` lists it with the other patches that
# change what the parser builds on purpose, and says the bound there.
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
  Subject: [PATCH 12/14] Ask the "in table" character rule for its current node

  The spec's "in table" mode gates its character rule on the current node: "A character
  token, if the current node is table, tbody, template, tfoot, thead, or tr element" goes to
  "in table text", and anything else is "Parse error. Enable foster parenting, process the
  token using the rules for the 'in body' insertion mode, and then disable foster parenting"
  (parsing.html#parsing-main-intable, fetched 2026-10-17). The pinned base takes the first
  branch for every character token it sees in that mode, whatever the current node is.

  What that costs is a text-node split. A run written where the current node is something
  else — a custom element foster parented out of the table, say — is accumulated in
  "in table text" and flushed when the next token arrives, so a token that is then ignored
  (`</h>` below) ends the run and the next character starts a new node. The spec's route
  keeps one run: the character is handled by the in-body rule, in the buffer that is already
  open. `<table><r>x</h>e` reads `[{"r", [], ["xe"]}, {"table", [], []}]` with the condition
  and `[{"r", [], ["x", "e"]}, {"table", [], []}]` without it, and Nokogiri's fork — which
  has the condition, and `GUMBO_TOKEN_NULL` in it — parses the first.

  The `[{"r", …}]` shape is not invented for this patch: it is one of the 1,058 stored bodies
  a Rails port carries, and it was the last body whose tree that port's own reference parser
  disagreed with this base on, once the branch's two compatibility patches are out of the
  way. The tree is the same shape `main` produces for the other 1,057; this makes it the
  same for that one too.

  The fall-through already does what the spec asks for a character token: the "anything
  else" arm at the end of `handle_in_table` records the parse error, enables foster
  parenting, calls `handle_in_body`, and disables it again. Nothing else is added here, and
  `GUMBO_TOKEN_NULL` goes in the condition because in-table-text's own NULL rule — parse
  error, ignore the token — is the one the spec gives for it.
  ---
  """,
  subs: [
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          if (token->type == GUMBO_TOKEN_CHARACTER ||
              token->type == GUMBO_TOKEN_WHITESPACE) {
            // The "pending table character tokens" list described in the spec is
        """),
      to:
        t.(~S"""
          if ((token->type == GUMBO_TOKEN_CHARACTER ||
                  token->type == GUMBO_TOKEN_WHITESPACE ||
                  token->type == GUMBO_TOKEN_NULL) &&
              node_tag_in_set(get_current_node(parser),
                  (gumbo_tagset){TAG(TABLE), TAG(TBODY), TAG(TEMPLATE), TAG(TFOOT),
                      TAG(THEAD), TAG(TR)})) {
            // The "pending table character tokens" list described in the spec is
        """)
    }
  ]
}
