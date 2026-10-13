# The 0005 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0005-stack-budget-guard.patch. Ported one to one
# from the Python generator when that tooling was replaced, so the header below is the
# same prose and the substitutions are the same ones.
#
# `priors` mirrors what that generator did: 0005 was written after the earlier patches existed, so it diffs against the patched tree.
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
  Subject: [PATCH 5/5] Stop parsing when the stack budget is nearly spent

  Everything else in this series removes a recursion or bounds a cost. This one is for
  the recursion nobody has found yet: a depth-proportional walk in code we do not own,
  whose depth is a function of the input and whose frame size is unknown, is the one
  failure this library cannot rule out by construction. The alternative — a nesting-depth
  cap, which is what Blink, WebKit, Gecko and Nokogiri's gumbo do — would bound it, at the
  price of refusing or reshaping documents this library parses today, and the budget
  below already keeps those documents affordable.

  So the parse is told how much stack it has and stops before it runs out. The caller
  knows the number: this library's NIF measures the thread's stack for the sized-thread
  decision in c_src/gumbo_parse_stack.c, and passes what is left after a reserve.
  GumboOptions.stack_budget is that number, zero meaning no guard.

  The check happens in three places, and the places are the interesting part:

    * handle_token, once per token. That covers any recursion that spans tokens, which
      is nearly all of them — the frameset body-removal walk that used to kill the VM
      was the exception, and patch 0001 removed it.
    * clone_node_recursively, which is the one recursion still known to be
      depth-proportional: it returns NULL, which its caller already handles, and the
      shape stops growing.
    * the parse loop's condition, which is where the parse actually stops. It is the
      same exit as stop_on_first_error, so finish_parsing and teardown run as usual and
      the tree stays consistent; GumboOutput.too_deep reports what happened, and this
      library answers {:error, :too_deep} rather than handing back a partial tree.

  A guard cannot cover a recursion that goes deep inside one token's handling without
  passing through those three places, and saying so is the honest half of this patch.
  What it does cover is every recursion whose depth the parser can observe, which is what
  "the budget with a detector" means: the guard is what turns a mis-estimated budget from
  a crash into a refusal.
  ---
  """,
  subs: [
    %{
      file: "gumbo.h",
      count: 1,
      from:
        t.(~S"""
          unsigned int max_attributes;
        } GumboOptions;
        """),
      to:
        t.(~S"""
          unsigned int max_attributes;

          /**
           * How much C stack the parse may use, in bytes, or 0 for no limit. The parser
           * stops parsing when it comes within a frame of exhausting this, and reports it
           * through GumboOutput.too_deep. It exists for the recursion nobody has found: a
           * depth-proportional walk whose frame size is unknown cannot be ruled out by
           * arithmetic, so it is caught by a guard instead. The caller is the one who knows
           * the number, because the caller is the one that chose the thread.
           */
          size_t stack_budget;
        } GumboOptions;

        /**
         * Defined so that a harness compiled against this header and one compiled against the
         * pinned header can tell each other apart at compile time: the field above does not exist
         * there, and a differential harness has to be built against both.
         */
        #define GUMBO_HAS_STACK_GUARD 1
        """)
    },
    %{
      file: "gumbo.h",
      count: 1,
      from:
        t.(~S"""
          bool too_many_attributes;
        """),
      to:
        t.(~S"""
          bool too_many_attributes;

          /**
           * True if the parse stopped early because it reached GumboOptions.stack_budget. The
           * tree is whatever had been built, which is why this library refuses the parse
           * rather than returning it.
           */
          bool too_deep;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
            8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML, 1024};
        """),
      to:
        t.(~S"""
            8, false, -1, GUMBO_TAG_LAST, GUMBO_NAMESPACE_HTML, 1024, 0};
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          output->root = NULL;
          output->too_many_attributes = false;
        """),
      to:
        t.(~S"""
          output->root = NULL;
          output->too_many_attributes = false;
          output->too_deep = false;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          unsigned int _open_p_count;
        """),
      to:
        t.(~S"""
          unsigned int _open_p_count;

          /**
           * Where the stack budget runs out, or NULL when there is no guard. The parse
           * compares the address of one of its own locals against it: below this line there
           * is not enough stack left to finish parsing and tear the tree down, so it stops.
           */
          const char* _stack_limit;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          gumbo_vector_init(parser, 10, &parser_state->_open_elements);
          parser_state->_open_p_count = 0;
        """),
      to:
        t.(~S"""
          gumbo_vector_init(parser, 10, &parser_state->_open_elements);
          parser_state->_open_p_count = 0;
          parser_state->_stack_limit = NULL;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
        static void parser_state_init(GumboParser* parser) {
        """),
      to:
        t.(~S"""
        /* True when the parse has come within a frame of the budget, in which case it stops:
           what is left of the stack is what finish_parsing and the teardown need. The address
           of a local in this function is one frame deeper than the caller's, which errs on the
           side of stopping early. */
        // noinline, and that is load-bearing rather than an optimisation hint: this function has
        // to own a frame for its frame address to mean anything. Inlined, the builtin reports the
        // caller's frame instead, and a compiler that can see it is loop-invariant hoists it out of
        // the token loop — which is exactly how the first version of this guard compiled to a
        // comparison that was always false at -O2 while working at -O0.
        __attribute__((noinline)) static bool stack_budget_spent(GumboParser* parser) {
          const char* limit = parser->_parser_state->_stack_limit;
          if (limit == NULL) {
            return false;
          }
          /* The frame address, not the address of a local: a local that is not used again has a
             dead slot, and the optimiser is free to hand it to the next call, which is how the
             first two versions of this guard came to compare two identical addresses and never
             fire. A frame address is fresh in every frame and cannot be shared. */
          if ((const char*) __builtin_frame_address(0) < limit) {
            parser->_output->too_deep = true;
            return true;
          }
          return false;
        }

        static void parser_state_init(GumboParser* parser) {
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          gumbo_tokenizer_state_init(&parser, buffer, length);
          parser_state_init(&parser);
        """),
      to:
        t.(~S"""
          gumbo_tokenizer_state_init(&parser, buffer, length);
          parser_state_init(&parser);
          parser._parser_state->_stack_limit = options->stack_budget
                                                   ? (const char*) __builtin_frame_address(0) -
                                                         options->stack_budget
                                                   : NULL;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
        static bool handle_token(GumboParser* parser, GumboToken* token) {
        """),
      to:
        t.(~S"""
        static bool handle_token(GumboParser* parser, GumboToken* token) {
          if (stack_budget_spent(parser)) {
            return false;
          }
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
        static GumboNode* clone_node_recursively(GumboParser* parser, const GumboNode* src) {
          if (!src) {
            return NULL;
          }
        """),
      to:
        t.(~S"""
        static GumboNode* clone_node_recursively(GumboParser* parser, const GumboNode* src) {
          if (!src) {
            return NULL;
          }
          if (stack_budget_spent(parser)) {
            /* The caller appends the clone only when this is non-NULL, so returning NULL
               stops the subtree growing instead of half-building it. */
            return NULL;
          }
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          } while ((token.type != GUMBO_TOKEN_EOF || state->_reprocess_current_token) &&
                   !(options->stop_on_first_error && has_error));
        """),
      to:
        t.(~S"""
          } while ((token.type != GUMBO_TOKEN_EOF || state->_reprocess_current_token) &&
                   !(options->stop_on_first_error && has_error) &&
                   !parser._output->too_deep);
        """)
    }
  ]
}
