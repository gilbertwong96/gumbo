# The 0015 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0015-duplicate-attribute-buffer.patch.
#
# `priors` is true: the duplicate branch this edits is 0004's own text — it is the scan that
# patch replaced with buckets — so the anchor is the patched tree, and `make check-parity`
# cannot list this patch with the others. It does not need to: the only documents it moves are
# ones with a duplicate attribute name followed by another name *and* a capped error list, and
# the parity harness runs both sides with gumbo's default (no cap), so the corpus cannot see it.
#
# The layout is mix format's, not hand-kept: re-indenting a heredoc and its terminator
# together leaves the value alone, which is why this file lives in .formatter.exs.
#
# Files touched, in the order the substitutions run: tokenizer.c

# The texts below are C, so they are written as heredocs and read as C. A heredoc's
# value ends with the newline before its terminator, which is exactly right for a text
# that ends with one; for the rest, `t/1` drops that single newline. No other shape
# occurs here, and `mix gumbo.patches --check` fails if a text is misrepresented.
t = &String.replace_suffix(&1, "\n", "")

%{
  priors: true,
  header: ~S"""
  From: patched for this project, not from upstream
  Subject: [PATCH 15/15] Reset the tag buffer where the duplicate attribute is dropped

  A duplicate attribute name is detected when its name state ends, and the name is dropped with a
  parse error. The pinned base resets the tag buffer inside `add_duplicate_attr_error`, after the
  copy that records the name in the error — but that function returns early when
  `gumbo_add_error` returns NULL, which is what a capped error list does
  (`max_errors: 0` is the case a caller reaches by asking for no errors at all). The name then
  stays in the tag buffer, and the next attribute name is appended to it: `<p a=1 a b=2>` reads
  `[{"a", "1"}, {"ab", "2"}]` with the cap and `[{"a", "1"}, {"b", "2"}]` without it.

  Nokogiri's fork has the same duplicate check and resets at the call site, after
  `add_duplicate_attr_error` returns, so it is unaffected by whether an error was recorded. This
  patch moves the reset there: the caller drops the name, the error still carries it, and the
  buffer is empty either way.

  The caller is the one place `add_duplicate_attr_error` is called from, so the reset happens
  exactly once. Measured on a Rails port's stored corpus, which parses with no errors recorded,
  five of its 1,058 bodies read differently before this patch and hold a duplicate attribute name
  followed by another name; the port's own reference parser agrees with them after it.

  Nothing here is visible with gumbo's default error handling (no cap), which is why
  `make check-parity` cannot see this patch and why its evidence is a test rather than the corpus.
  ---
  """,
  subs: [
    %{
      file: "tokenizer.c",
      count: 1,
      from:
        t.(
          "  copy_over_tag_buffer(parser, &error->v.duplicate_attr.name);\n  reinitialize_tag_buffer(parser);\n}\n"
        ),
      to: t.("  copy_over_tag_buffer(parser, &error->v.duplicate_attr.name);\n}\n")
    },
    %{
      file: "tokenizer.c",
      count: 1,
      from:
        t.(
          "      // Identical attribute; bail.\n" <>
            "      add_duplicate_attr_error(parser, attr->name, i, attributes->length);\n" <>
            "      tag_state->_drop_next_attr_value = true;\n" <>
            "      return false;\n"
        ),
      to:
        t.(
          "      // Identical attribute; bail. The name is dropped here rather than inside\n" <>
            "      // add_duplicate_attr_error, which returns before its own reset when no error\n" <>
            "      // can be recorded — a capped error list, `max_errors: 0` — and the name would\n" <>
            "      // then stay in the tag buffer for the next attribute name to be appended to.\n" <>
            "      // Nokogiri's fork resets here for the same reason.\n" <>
            "      add_duplicate_attr_error(parser, attr->name, i, attributes->length);\n" <>
            "      reinitialize_tag_buffer(parser);\n" <>
            "      tag_state->_drop_next_attr_value = true;\n" <>
            "      return false;\n"
        )
    }
  ]
}
