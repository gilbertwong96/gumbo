defmodule Gumbo.Types do
  @moduledoc """
  Atom unions for the gumbo enums.

  Every enum is mapped to atoms by one mechanical rule, applied in
  `c_src/gumbo_atoms.c`: strip the family prefix, lowercase ASCII, keep
  underscores. `GUMBO_NODE_DOCUMENT` becomes `:document`,
  `GUMBO_INSERTION_MODE_IN_HEAD` becomes `:in_head`, and so on. The tag enum
  is the one exception: it has no family prefix and its names come from
  gumbo's own normalized tag table (`GUMBO_TAG_UNKNOWN` becomes `:unknown`,
  not `""`). See `Gumbo.Tag.t/0`.

  This module holds only types; the functions that produce these atoms live
  in the modules that own each concept.
  """

  @typedoc "`GumboNodeType`: `GUMBO_NODE_` stripped and lowercased."
  @type node_type ::
          :document
          | :element
          | :text
          | :cdata
          | :comment
          | :whitespace
          | :template
          | :processing_instruction

  @typedoc "`GumboNamespaceEnum`: `GUMBO_NAMESPACE_` stripped and lowercased."
  @type namespace :: :html | :svg | :mathml

  @typedoc "`GumboAttributeNamespaceEnum`: `GUMBO_ATTR_NAMESPACE_` stripped and lowercased."
  @type attribute_namespace :: :none | :xlink | :xml | :xmlns

  @typedoc "`GumboQuirksModeEnum`: `GUMBO_DOCTYPE_` stripped and lowercased."
  @type quirks_mode :: :no_quirks | :quirks | :limited_quirks

  @typedoc """
  `GumboParseFlags`: `GUMBO_INSERTION_` stripped and lowercased.

  These are single bits, so a node's parse flags are a subset of this union,
  not a single member.
  """
  @type parse_flag ::
          :normal
          | :by_parser
          | :implicit_end_tag
          | :implied
          | :converted_from_end_tag
          | :from_isindex
          | :from_image
          | :reconstructed_formatting_element
          | :adoption_agency_cloned
          | :adoption_agency_moved
          | :foster_parented

  @typedoc "`GumboErrorType`: `GUMBO_ERR_` stripped and lowercased."
  @type error_type ::
          :utf8_invalid
          | :utf8_truncated
          | :utf8_null
          | :numeric_char_ref_no_digits
          | :numeric_char_ref_without_semicolon
          | :numeric_char_ref_invalid
          | :named_char_ref_without_semicolon
          | :named_char_ref_invalid
          | :tag_starts_with_question
          | :tag_eof
          | :tag_invalid
          | :close_tag_empty
          | :close_tag_eof
          | :close_tag_invalid
          | :script_eof
          | :attr_name_eof
          | :attr_name_invalid
          | :attr_double_quote_eof
          | :attr_single_quote_eof
          | :attr_unquoted_eof
          | :attr_unquoted_right_bracket
          | :attr_unquoted_equals
          | :attr_after_eof
          | :attr_after_invalid
          | :duplicate_attr
          | :solidus_eof
          | :solidus_invalid
          | :dashes_or_doctype
          | :comment_eof
          | :comment_invalid
          | :comment_bang_after_double_dash
          | :comment_dash_after_double_dash
          | :comment_space_after_double_dash
          | :comment_end_bang_eof
          | :doctype_eof
          | :doctype_invalid
          | :doctype_space
          | :doctype_right_bracket
          | :doctype_space_or_right_bracket
          | :doctype_end
          | :parser
          | :unacknowledged_self_closing_tag

  @typedoc "`GumboTokenizerErrorState`: `GUMBO_ERR_TOKENIZER_` stripped and lowercased."
  @type tokenizer_state ::
          :data
          | :char_ref
          | :rcdata
          | :rawtext
          | :plaintext
          | :script
          | :tag
          | :self_closing_tag
          | :attr_name
          | :attr_value
          | :markup_declaration
          | :comment
          | :doctype
          | :cdata

  @typedoc "`GumboTokenType`: `GUMBO_TOKEN_` stripped and lowercased."
  @type token_type ::
          :doctype
          | :start_tag
          | :end_tag
          | :comment
          | :whitespace
          | :character
          | :cdata
          | :null
          | :eof
          | :processing_instruction

  @typedoc "`GumboInsertionMode`: `GUMBO_INSERTION_MODE_` stripped and lowercased."
  @type insertion_mode ::
          :initial
          | :before_html
          | :before_head
          | :in_head
          | :in_head_noscript
          | :after_head
          | :in_body
          | :text
          | :in_table
          | :in_table_text
          | :in_caption
          | :in_column_group
          | :in_table_body
          | :in_row
          | :in_cell
          | :in_template
          | :after_body
          | :in_frameset
          | :after_frameset
          | :after_after_body
          | :after_after_frameset
end
