# The 0002 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0002-open-element-queries.patch. Ported one to one
# from the Python generator when that tooling was replaced, so the header below is the
# same prose and the substitutions are the same ones.
#
# `priors` mirrors what that generator did: 0002 was written before the earlier patches existed, so it diffs against the pinned tree.
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
  priors: false,
  header: ~S"""
  From: patched for this project, not from upstream
  Subject: [PATCH 2/3] Answer the open-element queries in O(1) instead of walking the stack

  Two queries over the parser's stack of open elements are asked once per tag and
  answered by walking it, which makes the parse quadratic in nesting depth:
  measured, `<div>`*20000 takes 274 ms and `<b>`*20000 takes 75 ms, and the
  profiler puts 99.7% and 99% of that time in these two walks respectively.

    - has_an_element_in_button_scope(P), once per block-level start tag from
      maybe_implicitly_close_p_tag. It scans down to the nearest scope boundary,
      and a document nested with anything that is not a boundary has none, so it
      scans to the bottom every time. An open-p counter answers it without looking
      when no p is open at all, which is that document.

    - is_open_element(), once per formatting entry from
      reconstruct_active_formatting_elements and so once per tag. That one is a
      linear search of the whole stack for a pointer. A flag on the node answers it.

  Both answers are exactly what the walks would have returned, so tree construction
  is unchanged: the differential harness in c_src/test/parity_dump.c parses the same
  seeded corpus with this build and with the pinned sources and compares the trees
  node by node, and `make check-parity` runs it.

  The thing that can go wrong is a mutation of the stack that does not say so, which
  is why every mutation now goes through one of the five open_element_* functions
  and none of them touches _open_elements directly. The asserts in those functions
  catch a double push or a clear of a node that is not open, and they are live in
  the harness because nothing defines NDEBUG there.

  Upstream has no fix for this and neither does any engine: Blink, WebKit and Gecko
  cap the tree depth at 512 and reparent instead, and Nokogiri's gumbo exposes
  max_tree_depth (default 400). A depth cap would bound every walk at once, at the
  price of refusing or reshaping the deep documents this library parses today. This
  patch is the alternative that leaves tree construction alone.
  ---
  """,
  subs: [
    %{
      file: "gumbo.h",
      count: 1,
      from: ~S"""
        /**
         * A bitvector of flags containing information about why this element was
         * inserted into the parse tree, including a variety of special parse
         * situations.
         */
        GumboParseFlags parse_flags;
      """,
      to: ~S"""
        /**
         * A bitvector of flags containing information about why this element was
         * inserted into the parse tree, including a variety of special parse
         * situations.
         */
        GumboParseFlags parse_flags;

        /**
         * Internal to the tree builder: true while this node is in the parser's stack
         * of open elements. Kept here rather than answered by searching that stack,
         * because reconstruct_active_formatting_elements asks the question once per
         * formatting entry and so once per tag, and the stack is as deep as the
         * document is nested.
         */
        bool is_open;
      """
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          node->parse_flags = GUMBO_INSERTION_NORMAL;
          return node;
        """),
      to:
        t.(~S"""
          node->parse_flags = GUMBO_INSERTION_NORMAL;
          node->is_open = false;
          return node;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          GumboVector /*GumboNode*/ _open_elements;
        """),
      to:
        t.(~S"""
          GumboVector /*GumboNode*/ _open_elements;
          /**
           * How many HTML <p> elements are in _open_elements. The button-scope query
           * starts by walking that stack from the top; when no p is open at all the
           * answer is false without looking, which is the case for every block-level
           * start tag in a document nested with tags that are not p, i.e. exactly the
           * shape that made the parse quadratic.
           */
          unsigned int _open_p_count;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          gumbo_vector_init(parser, 10, &parser_state->_open_elements);
        """),
      to:
        t.(~S"""
          gumbo_vector_init(parser, 10, &parser_state->_open_elements);
          parser_state->_open_p_count = 0;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""

        static GumboNode* pop_current_node(GumboParser* parser) {
        """),
      to:
        t.(~S"""

        /* The stack of open elements is what every scope query and every "is this node
           still open" question reads, and both used to be answered by walking it: the
           button-scope check scans to the bottom when the document has no scope boundary
           above, once per block-level start tag, and is_open_element searched the whole
           stack once per formatting entry and so once per tag. Keep the two answers
           instead. The only way to get them wrong is to mutate the stack without saying
           so, which is why every mutation goes through one of the five functions below
           and none of them calls gumbo_vector_* on _open_elements directly. */
        static bool node_is_open_p(const GumboNode* node) {
          return node->type == GUMBO_NODE_ELEMENT &&
                 node->v.element.tag == GUMBO_TAG_P &&
                 node->v.element.tag_namespace == GUMBO_NAMESPACE_HTML;
        }

        static void open_element_clear(GumboParser* parser, GumboNode* node) {
          GumboParserState* state = parser->_parser_state;
          assert(node->is_open);
          node->is_open = false;
          if (node_is_open_p(node)) {
            assert(state->_open_p_count > 0);
            --state->_open_p_count;
          }
        }

        static void open_element_push(GumboParser* parser, GumboNode* node) {
          GumboParserState* state = parser->_parser_state;
          assert(!node->is_open);
          node->is_open = true;
          if (node_is_open_p(node)) {
            ++state->_open_p_count;
          }
          gumbo_vector_add(parser, (void*) node, &state->_open_elements);
        }

        static GumboNode* open_element_pop(GumboParser* parser) {
          GumboParserState* state = parser->_parser_state;
          GumboNode* node = (GumboNode*) gumbo_vector_pop(parser, &state->_open_elements);
          if (node != NULL) {
            open_element_clear(parser, node);
          }
          return node;
        }

        static void open_element_remove_at(GumboParser* parser, unsigned int index) {
          GumboParserState* state = parser->_parser_state;
          assert(index < state->_open_elements.length);
          open_element_clear(parser, (GumboNode*) state->_open_elements.data[index]);
          gumbo_vector_remove_at(parser, index, &state->_open_elements);
        }

        static void open_element_remove(GumboParser* parser, GumboNode* node) {
          GumboParserState* state = parser->_parser_state;
          /* The node is not always on the stack: the adoption agency algorithm removes
             elements it may already have taken out, and gumbo_vector_remove reports
             nothing about whether it removed anything, so ask where the node is first.
             This is the one place the patch still scans the stack, and it runs inside
             the adoption agency algorithm, which runs at most eight times per tag. */
          if (gumbo_vector_index_of(&state->_open_elements, node) < 0) {
            return;
          }
          open_element_clear(parser, node);
          gumbo_vector_remove(parser, node, &state->_open_elements);
        }

        static void open_element_insert_at(
            GumboParser* parser, GumboNode* node, unsigned int index) {
          GumboParserState* state = parser->_parser_state;
          assert(!node->is_open);
          node->is_open = true;
          if (node_is_open_p(node)) {
            ++state->_open_p_count;
          }
          gumbo_vector_insert_at(parser, node, index, &state->_open_elements);
        }

        static void open_element_replace_at(
            GumboParser* parser, unsigned int index, GumboNode* node) {
          GumboParserState* state = parser->_parser_state;
          GumboNode* previous = (GumboNode*) state->_open_elements.data[index];
          if (previous != node) {
            open_element_clear(parser, previous);
            assert(!node->is_open);
            node->is_open = true;
            if (node_is_open_p(node)) {
              ++state->_open_p_count;
            }
          }
          /* The tenth mutation site, and the one the first version of this patch missed:
             step 13.7 of the adoption agency algorithm swaps a clone in for the element
             it was cloned from, rather than pushing or removing. The assert in
             open_element_clear found it — the two answers were quietly wrong from then on,
             which changes what reconstruct_active_formatting_elements answers, which
             changes the tree. */
          state->_open_elements.data[index] = node;
        }

        static GumboNode* pop_current_node(GumboParser* parser) {
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          *new_node = *node;
          new_node->parent = NULL;
          new_node->index_within_parent = -1;
        """),
      to:
        t.(~S"""
          *new_node = *node;
          new_node->parent = NULL;
          new_node->index_within_parent = -1;
          /* The copy above carries is_open over too, and the node being cloned is open
             by definition here, so say plainly that the clone is not in the stack until
             something inserts it. A stale true would be silent: it only changes what
             reconstruct_active_formatting_elements answers, i.e. the shape of the tree. */
          new_node->is_open = false;
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from: ~S"""
      static void insert_element(GumboParser* parser, GumboNode* node,
          bool is_reconstructing_formatting_elements) {
        GumboParserState* state = parser->_parser_state;
      """,
      to: ~S"""
      static void insert_element(GumboParser* parser, GumboNode* node,
          bool is_reconstructing_formatting_elements) {
      """
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          GumboNode* current_node = gumbo_vector_pop(parser, &state->_open_elements);
        """),
      to:
        t.(~S"""
          GumboNode* current_node = open_element_pop(parser);
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          InsertionLocation location = get_appropriate_insertion_location(parser, NULL);
          insert_node(parser, node, location);
          gumbo_vector_add(parser, (void*) node, &state->_open_elements);
        """),
      to:
        t.(~S"""
          InsertionLocation location = get_appropriate_insertion_location(parser, NULL);
          insert_node(parser, node, location);
          open_element_push(parser, node);
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
            insert_node(parser, clone, location);
            gumbo_vector_add(
                parser, (void*) clone, &parser->_parser_state->_open_elements);
        """),
      to:
        t.(~S"""
            insert_node(parser, clone, location);
            open_element_push(parser, clone);
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
              if (formatting_index == -1) {
                // Step 13.6.
                gumbo_vector_remove_at(parser, node_index, &state->_open_elements);
                continue;
              }
        """),
      to:
        t.(~S"""
              if (formatting_index == -1) {
                // Step 13.6.
                open_element_remove_at(parser, node_index);
                continue;
              }
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
              assert(node_index >= 0);
              state->_open_elements.data[node_index] = node;
        """),
      to:
        t.(~S"""
              assert(node_index >= 0);
              open_element_replace_at(parser, (unsigned int) node_index, node);
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
            // Step 19.
            gumbo_vector_remove(parser, formatting_node, &state->_open_elements);
            int insert_at =
                gumbo_vector_index_of(&state->_open_elements, furthest_block) + 1;
            assert(insert_at >= 0);
            assert((unsigned int) insert_at <= state->_open_elements.length);
            gumbo_vector_insert_at(
                parser, new_formatting_node, insert_at, &state->_open_elements);
        """),
      to:
        t.(~S"""
            // Step 19.
            open_element_remove(parser, formatting_node);
            int insert_at =
                gumbo_vector_index_of(&state->_open_elements, furthest_block) + 1;
            assert(insert_at >= 0);
            assert((unsigned int) insert_at <= state->_open_elements.length);
            open_element_insert_at(parser, new_formatting_node, (unsigned int) insert_at);
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
            gumbo_vector_add(parser, state->_head_element, &state->_open_elements);
            bool result = handle_in_head(parser, token);
            gumbo_vector_remove(parser, state->_head_element, &state->_open_elements);
        """),
      to:
        t.(~S"""
            open_element_push(parser, state->_head_element);
            bool result = handle_in_head(parser, token);
            open_element_remove(parser, state->_head_element);
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
                void* last_element = gumbo_vector_remove_at(
                    parser, last_a, &state->_active_formatting_elements);
                gumbo_vector_remove(parser, last_element, &state->_open_elements);
        """),
      to:
        t.(~S"""
                GumboNode* last_element = (GumboNode*) gumbo_vector_remove_at(
                    parser, last_a, &state->_active_formatting_elements);
                open_element_remove(parser, last_element);
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
        static bool is_open_element(GumboParser* parser, const GumboNode* node) {
          GumboVector* open_elements = &parser->_parser_state->_open_elements;
          for (unsigned int i = 0; i < open_elements->length; ++i) {
            if (open_elements->data[i] == node) {
              return true;
            }
          }
          return false;
        }
        """),
      to:
        t.(~S"""
        static bool is_open_element(GumboParser* parser, const GumboNode* node) {
          (void)parser;
          return node->is_open;
        }
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
        static bool maybe_implicitly_close_p_tag(
            GumboParser* parser, GumboToken* token) {
          if (has_an_element_in_button_scope(parser, GUMBO_TAG_P)) {
        """),
      to:
        t.(~S"""
        static bool has_open_p_in_button_scope(GumboParser* parser) {
          /* The counter is the fast path and the walk is the answer: with no p on the
             stack at all the walk would reach the bottom and return false, which is the
             common case in a deeply nested document. */
          return parser->_parser_state->_open_p_count != 0 &&
                 has_an_element_in_button_scope(parser, GUMBO_TAG_P);
        }

        static bool maybe_implicitly_close_p_tag(
            GumboParser* parser, GumboToken* token) {
          if (has_open_p_in_button_scope(parser)) {
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
            if (!has_an_element_in_button_scope(parser, GUMBO_TAG_P)) {
              parser_add_parse_error(parser, token);
        """),
      to:
        t.(~S"""
            if (!has_open_p_in_button_scope(parser)) {
              parser_add_parse_error(parser, token);
        """)
    }
  ]
}
