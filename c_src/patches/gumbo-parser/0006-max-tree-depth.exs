# The 0006 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0006-max-tree-depth.patch. Ported one to one
# from the Python generator when that tooling was replaced, so the header below is the
# same prose and the substitutions are the same ones.
#
# `priors` mirrors what that generator did: 0006 was written after the earlier patches existed, so it diffs against the patched tree.
#
# The layout is mix format's, not hand-kept: re-indenting a heredoc and its terminator
# together leaves the value alone, which is why this file lives in .formatter.exs.
#
# Files touched, in the order the substitutions run: gumbo.h, parser.c

# The texts below are C, so they are written as heredocs and read as C. A heredoc's
# value ends with the newline before its terminator, which is exactly right for a text
# that ends with one; for the rest, `t/1` drops that single newline. No other shape
# occurs here, and `mix gumbo.patches --check` fails if a text is misrepresented.
t = &String.replace_suffix(&1, "\n", "")

%{
  priors: true,
  header: ~S"""
  From: patched for this project, not from upstream
  Subject: [PATCH 6/6] Cap the parse tree's depth, the lever Nokogiri's gumbo exposes

  Upstream gumbo has no ceiling on the parse tree's depth, and this library does not
  need one: the parse's recursion follows the input's nesting depth for its stack, not
  for its time, so a 200 000-level body fragment parses in 78 ms, linear in depth, and
  c_src/gumbo_parse_stack.c sizes or refuses the stack it needs. What this patch adds
  is the lever an application needs when it wants the tree its reference implementation
  builds: Nokogiri's vendored gumbo carries `max_tree_depth` (400 by default, and its
  Ruby layer translates a negative value to UINT_MAX and adds one for a fragment, to
  account for the implied `<html>`), and an application pinned to that reference cannot
  ask this parser for the same behaviour without it.

  So GumboOptions.max_tree_depth sets how many open elements the parse may have, and
  GumboOutput.tree_too_deep reports that it stopped because of it. Exceeding the limit
  terminates the token stream as if EOF had been reached, exactly as the reference
  does, because breaking out of the loop mid-parse leaves the document in an
  inconsistent state. Nothing else changes: the default is no limit, so a parse that
  sets nothing is bit-identical to the pin, which is what `make check-parity` asserts.
  """,
  subs: [
    %{
      file: "gumbo.h",
      count: 1,
      from:
        t.(~S"""
          size_t stack_budget;
        } GumboOptions;
        """),
      to:
        t.(~S"""
          size_t stack_budget;

          /**
           * The largest number of open elements the parse may have, or UINT_MAX (the -1
           * this library passes for it) for no limit. The comparison is against the parser's
           * open-element stack, so an implied <html> counts and a fragment's context element
           * counts too: a caller meaning "400 levels of content" passes 401 for a fragment,
           * which is what the reference implementation's Ruby layer does. Exceeding it
           * terminates the token stream as if EOF, so the tree is truncated at that point and
           * GumboOutput.tree_too_deep is set. There is no default ceiling here on purpose:
           * this patch adds a lever, and a parse that sets nothing must build exactly what
           * the unpatched parser builds.
           */
          unsigned int max_tree_depth;
        } GumboOptions;
        """)
    },
    %{
      file: "gumbo.h",
      count: 1,
      from:
        t.(~S"""
          bool too_deep;
        } GumboOutput;
        """),
      to:
        t.(~S"""
          bool too_deep;

          /**
           * True if the parse stopped because the open-element stack went past
           * GumboOptions.max_tree_depth. The tree is what had been built when the limit was
           * reached, which differs from what the parser builds without the cap, so this
           * library refuses such a parse rather than returning it.
           */
          bool tree_too_deep;
        } GumboOutput;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
        const GumboOptions kGumboDefaultOptions = {&malloc_wrapper, &free_wrapper, NULL,
            8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML, 1024, 0};
        """),
      to:
        t.(~S"""
        const GumboOptions kGumboDefaultOptions = {&malloc_wrapper, &free_wrapper, NULL,
            8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML, 1024, 0,
            (unsigned int) -1};
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          output->too_deep = false;
        """),
      to:
        t.(~S"""
          output->too_deep = false;
          output->tree_too_deep = false;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          int loop_count = 0;

          GumboToken token;
        """),
      to:
        t.(~S"""
          int loop_count = 0;
          const unsigned int max_tree_depth = options->max_tree_depth;

          GumboToken token;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
              has_error = !gumbo_lex(&parser, &token) || has_error;
            }
        """),
      to:
        t.(~S"""
              // If the tree depth limit has been exceeded, proceed as if EOF has been
              // reached: the loop is left to finish the parse normally, because breaking out
              // of it here leaves the document in an inconsistent state.
              if (state->_open_elements.length > max_tree_depth) {
                parser._output->tree_too_deep = true;
                token.type = GUMBO_TOKEN_EOF;
              } else {
                has_error = !gumbo_lex(&parser, &token) || has_error;
              }
            }
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
                   !(options->stop_on_first_error && has_error) &&
                   !parser._output->too_deep);
        """),
      to:
        t.(~S"""
                   !(options->stop_on_first_error && has_error) &&
                   !parser._output->too_deep &&
                   !parser._output->tree_too_deep);
        """)
    }
  ]
}
