# The 0003 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0003-cap-error-tag-stack.patch. Ported one to one
# from the Python generator when that tooling was replaced, so the header below is the
# same prose and the substitutions are the same ones.
#
# `priors` mirrors what that generator did: 0003 was written before the earlier patches existed, so it diffs against the pinned tree.
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
  Subject: [PATCH 3/3] Cap what one error keeps of the open-element stack

  gumbo records one parser error per unclosed element at EOF, and one per unmatched
  end tag, and each error copied the whole open-element stack into itself. With the
  stack as deep as the document is nested, an input of n bytes could therefore cost
  n^2 entries: measured with a counting allocator, 100 KB of unclosed <div> produced
  20 000 errors and 400 040 000 stack entries (3.2 GB), and the same depth followed by
  20 000 unmatched </p> produced 800 080 000 entries (6.4 GB) — neither is a corner
  case, and neither is bounded by a limit on the input's length.

  Only the innermost stack entries are kept now, at most 32 of them, so the cost of
  the error vector is bounded by the number of errors gumbo is willing to record
  (`max_errors`, 100 by default in this library) times 32 entries. The alternative —
  bounding the nesting depth, which is what Blink, WebKit, Gecko and Nokogiri's gumbo
  do — would bound this too, but it changes which documents parse.

  This is a change to what an error carries, not to what the parser builds: the
  differential harness in c_src/test/parity_dump.c compares trees and error positions,
  not tag stacks, and `make check-parity` still passes. The cap is visible to a caller
  that asks for the stack: `Gumbo.Error.parser_error/1` returns at most 32 tags for an
  error deep in a document, and the rendered message lists at most those.
  ---
  """,
  subs: [
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
        static void* malloc_wrapper(void* unused, size_t size) { return malloc(size); }
        """),
      to:
        t.(~S"""
        /* How much of the stack of open elements one error keeps. An error used to
           keep all of it, and errors arrive one per unclosed element or unmatched end tag,
           which made the error vector cost the square of the input: 100 KB of unclosed
           <div> measured 400 040 000 entries and 3.2 GB. */
        #define GUMBO_ERROR_TAG_STACK_LIMIT 32

        static void* malloc_wrapper(void* unused, size_t size) { return malloc(size); }
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          GumboParserState* state = parser->_parser_state;
          extra_data->parser_state = state->_insertion_mode;
          gumbo_vector_init(
              parser, state->_open_elements.length, &extra_data->tag_stack);
          for (unsigned int i = 0; i < state->_open_elements.length; ++i) {
            const GumboNode* node = state->_open_elements.data[i];
            assert(
                node->type == GUMBO_NODE_ELEMENT || node->type == GUMBO_NODE_TEMPLATE);
            gumbo_vector_add(
                parser, (void*) node->v.element.tag, &extra_data->tag_stack);
          }
          return error;
        """),
      to:
        t.(~S"""
          GumboParserState* state = parser->_parser_state;
          extra_data->parser_state = state->_insertion_mode;
          /* The innermost entries, which are the error's own context; the outer ones are
             the document's skeleton and are the same for every error in it. The vector is
             sized for what is kept, not for the stack, so a deep error allocates 32 entries
             and not one per level. */
          unsigned int stack_length = state->_open_elements.length;
          unsigned int kept = (stack_length < GUMBO_ERROR_TAG_STACK_LIMIT)
                                  ? stack_length
                                  : (unsigned int) GUMBO_ERROR_TAG_STACK_LIMIT;
          gumbo_vector_init(parser, kept, &extra_data->tag_stack);
          for (unsigned int i = stack_length - kept; i < stack_length; ++i) {
            const GumboNode* node = state->_open_elements.data[i];
            assert(
                node->type == GUMBO_NODE_ELEMENT || node->type == GUMBO_NODE_TEMPLATE);
            gumbo_vector_add(
                parser, (void*) node->v.element.tag, &extra_data->tag_stack);
          }
          return error;
        """)
    }
  ]
}
