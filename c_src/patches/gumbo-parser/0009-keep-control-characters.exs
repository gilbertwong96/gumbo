# The 0009 generator: what it substitutes, and the count each substitution must
# match. `mix gumbo.patches` reads this, applies the earlier patches when `priors` is
# true, runs the substitutions in order, and writes 0009-keep-control-characters.patch.
# This one is about the input stream's decoder: the pin replaces the characters the
# spec calls parse errors instead of keeping them, and calls all of them UTF8_INVALID.
#
# `priors` mirrors what the earlier generators did: 0009 edits text no earlier patch moves,
# so it diffs against the pinned tree.
#
# The layout is mix format's, not hand-kept: re-indenting a heredoc and its terminator
# together leaves the value alone, which is why this file lives in .formatter.exs.
#
# Files touched, in the order the substitutions run: utf8.h, utf8.c, error.h, error.c

# The texts below are C, so they are written as heredocs and read as C. A heredoc's
# value ends with the newline before its terminator, which is exactly right for a text
# that ends with one; for the rest, `t/1` drops that single newline. No other shape
# occurs here, and `mix gumbo.patches --check` fails if a text is misrepresented.
t = &String.replace_suffix(&1, "\n", "")

%{
  priors: false,
  header: ~S"""
  From: patched for this project, not from upstream
  Subject: [PATCH 9/9] Keep the characters the spec only calls parse errors

  The input stream's decoder replaces two groups of characters with U+FFFD and
  reports every one of them as GUMBO_ERR_UTF8_INVALID:

      (c >= 0x1 && c <= 0x8) || c == 0xB || (c >= 0xE && c <= 0x1F) ||
      (c >= 0x7F && c <= 0x9F) || (c >= 0xFDD0 && c <= 0xFDEF) ||
      ((c & 0xFFFF) == 0xFFFE) || ((c & 0xFFFF) == 0xFFFF)

  The predicate's own comment says it is "the list of characters forbidden by the
  HTML5 spec". They are forbidden as parse errors; the spec keeps them. Only a byte
  sequence that is not valid UTF-8 becomes U+FFFD. So a control byte pasted into a
  document — a truncated file, a terminal escape sequence — comes back as U+FFFD in
  the tree here:

      <p>bell\x07 esc\x1b del\x7f c1\xc2\x85</p>

  keeps those bytes in the reference and writes four replacement characters here.

  Nokogiri's gumbo — an internal fork of lua-gumbo's, not the 0.14.1 sources with
  Nokogumbo's patches on top — keeps the character and records what it is:
  GUMBO_ERR_CONTROL_CHARACTER_IN_INPUT_STREAM with "Input contains prohibited
  control code point U+%04X." for a control, and GUMBO_ERR_NONCHARACTER_IN_INPUT_STREAM
  for a noncharacter. This patch does the same, and reports the code point the decoder
  computed rather than the bytes under the cursor: the value was built from the bytes,
  so U+0085 reported 0xC285 and U+FDD0 reported 0xEFB790.

  The set of characters reported does not move — utf8_is_invalid_code_point is now the
  union of the two new predicates, which is what char_ref.c wants for a numeric
  character reference — and neither does a sequence that is not valid UTF-8, which the
  DFA's reject branch still replaces. What moves is the text of any document holding
  one of these characters, and the type of the error it produces; the corpus this
  project's parity gate uses holds neither, which is why this patch is held by
  `test/gumbo/control_characters_test.exs`.

  The two enum members go at the end of GumboErrorType on purpose: this library
  indexes a table of atoms by that enum, so appending keeps every existing value
  where it was.
  ---
  """,
  subs: [
    %{
      file: "utf8.h",
      count: 1,
      from:
        t.(~S"""
        // Returns true if this Unicode code point is in the list of characters
        // forbidden by the HTML5 spec, such as NUL bytes and undefined control chars.
        bool utf8_is_invalid_code_point(int c);
        """),
      to:
        t.(~S"""
        // Returns true if this Unicode code point is in the list of characters
        // forbidden by the HTML5 spec, such as NUL bytes and undefined control chars.
        // The spec forbids them as parse errors and keeps them, so this is a question
        // about which error to report, not about whether to replace the character:
        // utf8_is_control and utf8_is_noncharacter split the set to say which one it is.
        bool utf8_is_invalid_code_point(int c);

        // Returns true if this Unicode code point is one of the controls the spec calls
        // a parse error: C0 except the whitespace it allows, and C1 with DEL.
        bool utf8_is_control(int c);

        // Returns true if this Unicode code point is a noncharacter.
        bool utf8_is_noncharacter(int c);
        """)
    },
    %{
      file: "utf8.c",
      count: 1,
      from:
        t.(~S"""
        bool utf8_is_invalid_code_point(int c) {
          return (c >= 0x1 && c <= 0x8) || c == 0xB || (c >= 0xE && c <= 0x1F) ||
                 (c >= 0x7F && c <= 0x9F) || (c >= 0xFDD0 && c <= 0xFDEF) ||
                 ((c & 0xFFFF) == 0xFFFE) || ((c & 0xFFFF) == 0xFFFF);
        }
        """),
      to:
        t.(~S"""
        bool utf8_is_invalid_code_point(int c) {
          return utf8_is_control(c) || utf8_is_noncharacter(c);
        }

        // The set is the one this predicate held before it was split, so the characters
        // reported are the same ones. They are kept now, which is the change.
        bool utf8_is_control(int c) {
          return (c >= 0x1 && c <= 0x8) || c == 0xB || (c >= 0xE && c <= 0x1F) ||
                 (c >= 0x7F && c <= 0x9F);
        }

        bool utf8_is_noncharacter(int c) {
          return (c >= 0xFDD0 && c <= 0xFDEF) || ((c & 0xFFFF) == 0xFFFE) ||
                 ((c & 0xFFFF) == 0xFFFF);
        }
        """)
    },
    %{
      file: "utf8.c",
      count: 1,
      from:
        t.(~S"""
        static void add_error(Utf8Iterator* iter, GumboErrorType type) {
        """),
      to:
        t.(~S"""
        // As add_error, for a code point the decoder did compute. The loop below builds the
        // value out of the bytes under the cursor, which is right for a sequence that is not
        // valid UTF-8 and wrong for one that is: it made U+0085 report 0xC285.
        static void add_error_for_codepoint(
            Utf8Iterator* iter, GumboErrorType type, int code_point) {
          GumboParser* parser = iter->_parser;

          GumboError* error = gumbo_add_error(parser);
          if (!error) {
            return;
          }
          error->type = type;
          error->position = iter->_pos;
          error->original_text = iter->_start;
          error->v.codepoint = (uint64_t) code_point;
        }

        static void add_error(Utf8Iterator* iter, GumboErrorType type) {
        """)
    },
    %{
      file: "utf8.c",
      count: 1,
      from:
        t.(~S"""
              if (utf8_is_invalid_code_point(code_point)) {
                add_error(iter, GUMBO_ERR_UTF8_INVALID);
                code_point = kUtf8ReplacementChar;
              }
        """),
      to:
        t.(~S"""
              if (utf8_is_noncharacter(code_point)) {
                add_error_for_codepoint(
                    iter, GUMBO_ERR_NONCHARACTER_IN_INPUT_STREAM, code_point);
              } else if (utf8_is_control(code_point)) {
                add_error_for_codepoint(
                    iter, GUMBO_ERR_CONTROL_CHARACTER_IN_INPUT_STREAM, code_point);
              }
        """)
    },
    %{
      file: "error.h",
      count: 1,
      from:
        t.(~S"""
          GUMBO_ERR_DOCTYPE_END,
          GUMBO_ERR_PARSER,
          GUMBO_ERR_UNACKNOWLEDGED_SELF_CLOSING_TAG,
        } GumboErrorType;
        """),
      to:
        t.(~S"""
          GUMBO_ERR_DOCTYPE_END,
          GUMBO_ERR_PARSER,
          GUMBO_ERR_UNACKNOWLEDGED_SELF_CLOSING_TAG,

          // Kept at the end so the values the parser already produces do not move: this
          // library indexes a table of atoms by this enum, and appending leaves every
          // existing value where it was.
          GUMBO_ERR_CONTROL_CHARACTER_IN_INPUT_STREAM,
          GUMBO_ERR_NONCHARACTER_IN_INPUT_STREAM,
        } GumboErrorType;
        """)
    },
    %{
      file: "error.h",
      count: 1,
      from:
        t.(~S"""
            // The code point we encountered, for:
            // * GUMBO_ERR_UTF8_INVALID
            // * GUMBO_ERR_UTF8_TRUNCATED
            // * GUMBO_ERR_NUMERIC_CHAR_REF_WITHOUT_SEMICOLON
            // * GUMBO_ERR_NUMERIC_CHAR_REF_INVALID
            uint64_t codepoint;
        """),
      to:
        t.(~S"""
            // The code point we encountered, for:
            // * GUMBO_ERR_UTF8_INVALID
            // * GUMBO_ERR_UTF8_TRUNCATED
            // * GUMBO_ERR_NUMERIC_CHAR_REF_WITHOUT_SEMICOLON
            // * GUMBO_ERR_NUMERIC_CHAR_REF_INVALID
            // * GUMBO_ERR_CONTROL_CHARACTER_IN_INPUT_STREAM
            // * GUMBO_ERR_NONCHARACTER_IN_INPUT_STREAM
            uint64_t codepoint;
        """)
    },
    %{
      file: "error.c",
      count: 1,
      from:
        t.(~S"""
          switch (error->type) {
            case GUMBO_ERR_UTF8_INVALID:
        """),
      to:
        t.(~S"""
          switch (error->type) {
            case GUMBO_ERR_CONTROL_CHARACTER_IN_INPUT_STREAM:
              print_message(parser, output,
                  "Input contains prohibited control code point U+%04X",
                  (unsigned int) error->v.codepoint);
              break;
            case GUMBO_ERR_NONCHARACTER_IN_INPUT_STREAM:
              print_message(parser, output,
                  "Input contains prohibited noncharacter U+%04X",
                  (unsigned int) error->v.codepoint);
              break;
            case GUMBO_ERR_UTF8_INVALID:
        """)
    }
  ]
}
