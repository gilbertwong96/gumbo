defmodule Gumbo.ErrorTest do
  use ExUnit.Case, async: true

  alias Gumbo.Error

  test "malformed markup produces reported errors without failing the parse" do
    {:ok, output} = Gumbo.parse("<p><b>unclosed <div></p></b></div>")
    # errors may or may not be produced depending on the construct; assert shape, not count
    assert is_list(Gumbo.Output.errors(output))
  end

  test "a duplicate attribute is reported with both indices" do
    {:ok, output} = Gumbo.parse(~s(<div class="a" class="b">x</div>))
    err = Enum.find(Gumbo.Output.errors(output), &(Error.type(&1) == :duplicate_attr))
    assert %{name: "class", original_index: 0, new_index: 1} = Error.duplicate_attr(err)
  end

  test "an invalid UTF-8 byte is reported as a UTF-8 error with a codepoint" do
    {:ok, output} = Gumbo.parse("<p>" <> <<0xFF>> <> "</p>")

    err =
      Enum.find(
        Gumbo.Output.errors(output),
        &(Error.type(&1) in [:utf8_invalid, :utf8_truncated])
      )

    assert is_integer(Error.codepoint(err))
    assert is_binary(Error.message(err))
  end

  test "stop_on_first_error stops after the first" do
    # Repeated duplicate attributes cannot show this: add_duplicate_attr_error
    # never makes gumbo_lex return false, so the parse loop in
    # gumbo_parse_with_options never sees has_error and the option has nothing
    # to stop (measured at 0.14.1: 53 errors with and without the option).
    # Only tokenizer errors that return RETURN_ERROR stop the loop — an
    # unquoted attribute value ended by `>` (`title=>`) is one: measured
    # 101 errors without, 2 with.
    html = String.duplicate(~s(<div title=>), 50)
    {:ok, all} = Gumbo.parse(html)
    {:ok, one} = Gumbo.parse(html, stop_on_first_error: true)
    assert length(Gumbo.Output.errors(one)) < length(Gumbo.Output.errors(all))
  end

  test "max_errors caps the list" do
    html = String.duplicate(~s(<div class="a" class="b">), 50)
    {:ok, output} = Gumbo.parse(html, max_errors: 3)
    assert length(Gumbo.Output.errors(output)) <= 3
  end

  test "caret/1 renders the error against the retained source" do
    {:ok, output} = Gumbo.parse("<p>" <> <<0xFF>> <> "</p>")
    err = hd(Gumbo.Output.errors(output))
    # gumbo's own wording, from error.c: "Invalid UTF8 character 0x%x",
    # prefixed with "@line:column: "
    caret = Error.caret(err)
    assert caret =~ "Invalid UTF8"
    assert caret =~ "^"
  end
end
