# The 0012 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0012-legacy-in-select.patch. This one
# restores the "in select" insertion mode Nokogiri's gumbo has and the pin no longer does.
#
# `priors` is true because this is an upstream commit's reverse replayed on the patched
# tree: the anchor before `has_an_element_in_select_scope` is 0002's text, not the pin's,
# and the diff is against the pin plus 0001-0011, the way the build applies them. The cost
# is that `make check-parity` cannot add it to BEHAVIOUR_PATCHES, which applies its patches
# to the pin on its own; that gate states the bound instead, and the header below says
# where. See c_src/patches/README.md.
#
# The layout is mix format's, not hand-kept: re-indenting a heredoc and its terminator
# together leaves the value alone, which is why this file lives in .formatter.exs.
#
# Files touched, in the order the substitutions run: insertion_mode.h, parser.c

# The texts below are C, so they are written as heredocs and read as C. A heredoc's
# value ends with the newline before its terminator, which is exactly right for a text
# that ends with one; for the rest, `t/1` drops that single newline. No other shape
# occurs here, and `mix gumbo.patches --check` fails if a text is misrepresented.
t = &String.replace_suffix(&1, "\n", "")

%{
  priors: true,
  header: ~S"""
  From: patched for this project, not from upstream
  Subject: [PATCH 12/12] Put the "in select" insertion mode back, for Nokogiri

  This is the reverse of the commit the pin follows. Upstream 7811944 ("fix parser to
  comply with most recent spec changes to <select> logic", 2025-09-17) removed the "in
  select" insertion mode with whatwg/html#10548, which folded its rules into "in body" and
  listed `select` among the scope types 0007 adds it to. Nokogiri's fork of gumbo still has
  the mode, so the same bytes parse into different trees: there, an element inside a select
  is dropped and its text merges with its neighbours; here, it is kept.

  The mode lives on this branch and nowhere else, because it is a whole insertion mode and
  not a knob: main keeps the current spec. NOKOGIRI-COMPAT.md is what the branch is for and
  what the port needs from it; this patch is that mode, restored from 7811944's own code,
  verbatim wherever the pin has not moved it since.

  What comes back: `handle_in_select`, `handle_in_select_in_table`,
  `has_an_element_in_select_scope`, `close_current_select`, the `select` case of
  `get_appropriate_insertion_mode`, the in-body `<select>` start tag that switches into the
  mode, and the two enum members with their kTokenHandlers entries. What goes away again are
  the three in-body rules 7811944 wrote in the mode's place: an `<input>`, an `<hr>`, an
  `<option>` or an `<optgroup>` start tag while a select is in scope, which the mode handles
  itself and which this branch therefore never reaches.

  Notes for review, since four details are not a plain revert:

  * The enum members go back between IN_CELL and IN_TEMPLATE, their old position, and so do
    the kTokenHandlers entries, so the numbering matches Nokogiri's and c_src/gumbo_atoms.c's
    member list stays a list in enum order. That file's count literal and lib/gumbo/types.ex
    move with it, in this branch's own commits rather than here: neither is part of the
    vendored copy this series patches. The numbering is observable, because a parser error
    reports the insertion mode it happened in.
  * A fragment whose context element is a `select` starts in the mode again, as it did before
    7811944: `get_appropriate_insertion_mode` substitutes the fragment context for the last
    open element, so the restored `select` case answers IN_SELECT for it.
  * The `</optgroup>` case keeps a bounds check the old code did without: it reads the stack's
    second entry only when the current node is an `option`, which is a stack of at least two,
    so the guard cannot change an answer. The pin's later commits guard the same shape in the
    same way, and the sanitizer gate reaches it.
  * Processing instructions are comment-like here, as in every other handler in this tree
    (`is_token_commentlike`); the old code could only see comments, because the token type did
    not exist yet. Nokogiri predates it too, and reads them as comments.

  0007's addition of SELECT to SCOPE_TAGS is left alone, and so are 0010's and 0011's shapes:
  on this branch the mode answers for a select, and the in-body rules those patches repaired
  are reached only for markup the mode would not see. `make check-parity` cannot put this
  patch in BEHAVIOUR_PATCHES, because 0012 is cumulative and that list is applied to the pin
  alone; the gate compares its baseline against the shipped build per document instead, and
  allows a difference only in a document whose tree holds a select, which is this patch's
  bound and is asserted to be non-empty. A document without one parses identically to the
  pinned sources, which is what the rest of the series keeps.
  ---
  """,
  subs: [
    %{
      file: "insertion_mode.h",
      count: 1,
      from:
        t.(~S"""
          GUMBO_INSERTION_MODE_IN_CELL,
          GUMBO_INSERTION_MODE_IN_TEMPLATE,
        """),
      to:
        t.(~S"""
          GUMBO_INSERTION_MODE_IN_CELL,
          GUMBO_INSERTION_MODE_IN_SELECT,
          GUMBO_INSERTION_MODE_IN_SELECT_IN_TABLE,
          GUMBO_INSERTION_MODE_IN_TEMPLATE,
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          switch (node->v.element.tag) {
            case GUMBO_TAG_TD:
        """),
      to:
        t.(~S"""
          switch (node->v.element.tag) {
            case GUMBO_TAG_SELECT: {
              if (is_last) {
                return GUMBO_INSERTION_MODE_IN_SELECT;
              }
              for (int i = index; i > 0; --i) {
                const GumboNode* ancestor = open_elements->data[i];
                if (node_html_tag_is(ancestor, GUMBO_TAG_TEMPLATE)) {
                  return GUMBO_INSERTION_MODE_IN_SELECT;
                }
                if (node_html_tag_is(ancestor, GUMBO_TAG_TABLE)) {
                  return GUMBO_INSERTION_MODE_IN_SELECT_IN_TABLE;
                }
              }
              return GUMBO_INSERTION_MODE_IN_SELECT;
            }
            case GUMBO_TAG_TD:
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""

        // http://www.whatwg.org/specs/web-apps/current-work/complete/tokenization.html#generate-implied-end-tags
        """),
      to:
        t.(~S"""

        // http://www.whatwg.org/specs/web-apps/current-work/multipage/parsing.html#has-an-element-in-select-scope
        static bool has_an_element_in_select_scope(GumboParser* parser, GumboTag tag) {
          return has_an_element_in_specific_scope(
              parser, 1, &tag, true, (gumbo_tagset){TAG(OPTGROUP), TAG(OPTION)});
        }

        // http://www.whatwg.org/specs/web-apps/current-work/complete/tokenization.html#generate-implied-end-tags
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
            return close_table_cell(parser, token, GUMBO_TAG_TH);
          }
        }

        """),
      to:
        t.(~S"""
            return close_table_cell(parser, token, GUMBO_TAG_TH);
          }
        }

        // This factors out the "act as if an end tag of tag name 'select' had been
        // seen" clause of the spec, since it's referenced in several places.  It pops
        // all nodes from the stack until the current <select> has been closed, then
        // resets the insertion mode appropriately.
        static void close_current_select(GumboParser* parser) {
          GumboNode* node = pop_current_node(parser);
          while (!node_html_tag_is(node, GUMBO_TAG_SELECT)) {
            node = pop_current_node(parser);
          }
          reset_insertion_mode_appropriately(parser);
        }

        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
            }
            if (has_an_element_in_scope(parser, GUMBO_TAG_SELECT)) {
              parser_add_parse_error(parser, token);
              while (!node_html_tag_is(pop_current_node(parser), GUMBO_TAG_SELECT));
              parser->_parser_state->_reprocess_current_token = true;
              return false;
            }
            if (!attribute_matches(&token->v.start_tag.attributes, "type", "hidden")) {
        """),
      to:
        t.(~S"""
            }
            if (!attribute_matches(&token->v.start_tag.attributes, "type", "hidden")) {
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
            bool result = maybe_implicitly_close_p_tag(parser, token);
            if (has_an_element_in_scope(parser, GUMBO_TAG_SELECT)) {
              generate_implied_end_tags(parser, GUMBO_TAG_LAST);
              if (has_an_element_in_scope_with_tagname(parser, 2, (GumboTag[]) {GUMBO_TAG_OPTION, GUMBO_TAG_OPTGROUP})) {
                parser_add_parse_error(parser, token);
              }
            }
            insert_element_from_token(parser, token);
        """),
      to:
        t.(~S"""
            bool result = maybe_implicitly_close_p_tag(parser, token);
            insert_element_from_token(parser, token);
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
          } else if (tag_is(token, kStartTag, GUMBO_TAG_SELECT)) {
            if (has_an_element_in_scope(parser, GUMBO_TAG_SELECT)) {
              parser_add_parse_error(parser, token);
              ignore_token(parser);
              while (!node_html_tag_is(pop_current_node(parser), GUMBO_TAG_SELECT));
            } else {
              reconstruct_active_formatting_elements(parser);
              insert_element_from_token(parser, token);
              set_frameset_not_ok(parser);
            }
            return true;
          } else if (tag_is(token, kStartTag, GUMBO_TAG_OPTION)) {
            if (has_an_element_in_scope(parser, GUMBO_TAG_SELECT)) {
              generate_implied_end_tags(parser, GUMBO_TAG_OPTGROUP);
              if (has_an_element_in_scope(parser, GUMBO_TAG_OPTION)) {
                parser_add_parse_error(parser, token);
              }
            } else {
              if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTION)) {
                pop_current_node(parser);
              }
            }
            reconstruct_active_formatting_elements(parser);
            insert_element_from_token(parser, token);
            return true;
          } else if (tag_is(token, kStartTag, GUMBO_TAG_OPTGROUP)) {
            if (has_an_element_in_scope(parser, GUMBO_TAG_SELECT)) {
              generate_implied_end_tags(parser, GUMBO_TAG_LAST);
              if (has_an_element_in_scope_with_tagname(parser, 2, (GumboTag[]) {
                    GUMBO_TAG_OPTION, GUMBO_TAG_OPTGROUP
                  })) {
                parser_add_parse_error(parser, token);
              }
            } else {
              if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTION)) {
                pop_current_node(parser);
              }
            }
        """),
      to:
        t.(~S"""
          } else if (tag_is(token, kStartTag, GUMBO_TAG_SELECT)) {
            reconstruct_active_formatting_elements(parser);
            insert_element_from_token(parser, token);
            set_frameset_not_ok(parser);
            GumboInsertionMode state = parser->_parser_state->_insertion_mode;
            if (state == GUMBO_INSERTION_MODE_IN_TABLE ||
                state == GUMBO_INSERTION_MODE_IN_CAPTION ||
                state == GUMBO_INSERTION_MODE_IN_TABLE_BODY ||
                state == GUMBO_INSERTION_MODE_IN_ROW ||
                state == GUMBO_INSERTION_MODE_IN_CELL) {
              set_insertion_mode(parser, GUMBO_INSERTION_MODE_IN_SELECT_IN_TABLE);
            } else {
              set_insertion_mode(parser, GUMBO_INSERTION_MODE_IN_SELECT);
            }
            return true;
          } else if (tag_in(token, kStartTag,
                         (gumbo_tagset){TAG(OPTION), TAG(OPTGROUP)})) {
            if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTION)) {
              pop_current_node(parser);
            }
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""

        // http://www.whatwg.org/specs/web-apps/current-work/multipage/tree-construction.html#parsing-main-intemplate
        """),
      to:
        t.(~S"""

        // http://www.whatwg.org/specs/web-apps/current-work/complete/tokenization.html#parsing-main-inselect
        static bool handle_in_select(GumboParser* parser, GumboToken* token) {
          if (token->type == GUMBO_TOKEN_NULL) {
            parser_add_parse_error(parser, token);
            ignore_token(parser);
            return false;
          } else if (token->type == GUMBO_TOKEN_CHARACTER ||
                     token->type == GUMBO_TOKEN_WHITESPACE) {
            insert_text_token(parser, token);
            return true;
          } else if (token->type == GUMBO_TOKEN_DOCTYPE) {
            parser_add_parse_error(parser, token);
            ignore_token(parser);
            return false;
          } else if (is_token_commentlike(token)) {
            append_commentlike_node(parser, get_current_node(parser), token);
            return true;
          } else if (tag_is(token, kStartTag, GUMBO_TAG_HTML)) {
            return handle_in_body(parser, token);
          } else if (tag_is(token, kStartTag, GUMBO_TAG_OPTION)) {
            if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTION)) {
              pop_current_node(parser);
            }
            insert_element_from_token(parser, token);
            return true;
          } else if (tag_is(token, kStartTag, GUMBO_TAG_OPTGROUP)) {
            if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTION)) {
              pop_current_node(parser);
            }
            if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTGROUP)) {
              pop_current_node(parser);
            }
            insert_element_from_token(parser, token);
            return true;
          } else if (tag_is(token, kStartTag, GUMBO_TAG_HR)) {
            if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTION)) {
              pop_current_node(parser);
            }
            if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTGROUP)) {
              pop_current_node(parser);
            }
            insert_element_from_token(parser, token);
            pop_current_node(parser);
            acknowledge_self_closing_tag(parser);
            return true;
          } else if (tag_is(token, kEndTag, GUMBO_TAG_OPTGROUP)) {
            GumboVector* open_elements = &parser->_parser_state->_open_elements;
            if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTION) &&
                open_elements->length >= 2 &&
                node_html_tag_is(open_elements->data[open_elements->length - 2],
                    GUMBO_TAG_OPTGROUP)) {
              pop_current_node(parser);
            }
            if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTGROUP)) {
              pop_current_node(parser);
              return true;
            } else {
              parser_add_parse_error(parser, token);
              ignore_token(parser);
              return false;
            }
          } else if (tag_is(token, kEndTag, GUMBO_TAG_OPTION)) {
            if (node_html_tag_is(get_current_node(parser), GUMBO_TAG_OPTION)) {
              pop_current_node(parser);
              return true;
            } else {
              parser_add_parse_error(parser, token);
              ignore_token(parser);
              return false;
            }
          } else if (tag_is(token, kEndTag, GUMBO_TAG_SELECT)) {
            if (!has_an_element_in_select_scope(parser, GUMBO_TAG_SELECT)) {
              parser_add_parse_error(parser, token);
              ignore_token(parser);
              return false;
            }
            close_current_select(parser);
            return true;
          } else if (tag_is(token, kStartTag, GUMBO_TAG_SELECT)) {
            parser_add_parse_error(parser, token);
            ignore_token(parser);
            if (has_an_element_in_select_scope(parser, GUMBO_TAG_SELECT)) {
              close_current_select(parser);
            }
            return false;
          } else if (tag_in(token, kStartTag,
                         (gumbo_tagset){TAG(INPUT), TAG(KEYGEN), TAG(TEXTAREA)})) {
            parser_add_parse_error(parser, token);
            if (!has_an_element_in_select_scope(parser, GUMBO_TAG_SELECT)) {
              ignore_token(parser);
            } else {
              close_current_select(parser);
              parser->_parser_state->_reprocess_current_token = true;
            }
            return false;
          } else if (tag_in(token, kStartTag,
                         (gumbo_tagset){TAG(SCRIPT), TAG(TEMPLATE)}) ||
                     tag_is(token, kEndTag, GUMBO_TAG_TEMPLATE)) {
            return handle_in_head(parser, token);
          } else if (token->type == GUMBO_TOKEN_EOF) {
            return handle_in_body(parser, token);
          } else {
            parser_add_parse_error(parser, token);
            ignore_token(parser);
            return false;
          }
        }

        // http://www.whatwg.org/specs/web-apps/current-work/complete/tokenization.html#parsing-main-inselectintable
        static bool handle_in_select_in_table(GumboParser* parser, GumboToken* token) {
          if (tag_in(token, kStartTag,
                  (gumbo_tagset){TAG(CAPTION), TAG(TABLE), TAG(TBODY), TAG(TFOOT),
                      TAG(THEAD), TAG(TR), TAG(TD), TAG(TH)})) {
            parser_add_parse_error(parser, token);
            close_current_select(parser);
            parser->_parser_state->_reprocess_current_token = true;
            return false;
          } else if (tag_in(token, kEndTag,
                         (gumbo_tagset){TAG(CAPTION), TAG(TABLE), TAG(TBODY),
                             TAG(TFOOT), TAG(THEAD), TAG(TR), TAG(TD), TAG(TH)})) {
            parser_add_parse_error(parser, token);
            if (!has_an_element_in_table_scope(parser, token->v.end_tag)) {
              ignore_token(parser);
              return false;
            } else {
              close_current_select(parser);
              // close_current_select already does the
              // reset_insertion_mode_appropriately
              // reset_insertion_mode_appropriately(parser);
              parser->_parser_state->_reprocess_current_token = true;
              return false;
            }
          } else {
            return handle_in_select(parser, token);
          }
        }

        // http://www.whatwg.org/specs/web-apps/current-work/multipage/tree-construction.html#parsing-main-intemplate
        """)
    },
    %{
      file: "parser.c",
      count: 1,
      from:
        t.(~S"""
            handle_in_cell,
            handle_in_template,
        """),
      to:
        t.(~S"""
            handle_in_cell,
            handle_in_select,
            handle_in_select_in_table,
            handle_in_template,
        """)
    }
  ]
}
