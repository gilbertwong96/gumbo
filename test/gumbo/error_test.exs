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

  test "a tokenizer error reports its state and codepoint" do
    {:ok, output} = Gumbo.parse(~s(<div title=>))

    err =
      Enum.find(
        Gumbo.Output.errors(output),
        &(Error.type(&1) == :attr_unquoted_right_bracket)
      )

    # 62 is the '>' that ended the attribute value; the tokenizer was still
    # in the attribute-name state when it saw the right bracket.
    assert %{state: :attr_name, codepoint: 62} = Error.tokenizer(err)
  end

  test "an unresolvable named character reference reports text, not a codepoint" do
    {:ok, output} = Gumbo.parse(~s(&notanentity;))

    err =
      Enum.find(
        Gumbo.Output.errors(output),
        &(Error.type(&1) == :named_char_ref_without_semicolon)
      )

    # "&not" resolves to a real entity without its semicolon; the v.text
    # member holds it and v.codepoint must stay unread (nil).
    assert Error.text(err) == "not"
    assert Error.codepoint(err) == nil
  end

  test "a parser error reports its insertion mode and open-tag stack" do
    {:ok, output} = Gumbo.parse("<div><span>")

    # The premature-EOF error: the one whose tag_stack is non-empty (the
    # initial-mode doctype error carries an empty one).
    err =
      Enum.find(Gumbo.Output.errors(output), fn error ->
        Error.type(error) == :parser and
          match?(%{tag_stack: [_ | _]}, Error.parser_error(error))
      end)

    assert %{
             input_type: :eof,
             input_tag: :unknown,
             insertion_mode: :in_body,
             tag_stack: [:html, :body, :div, :span]
           } = Error.parser_error(err)
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
    max = 3
    {:ok, output} = Gumbo.parse(html, max_errors: max)
    assert length(Gumbo.Output.errors(output)) <= max
  end

  # gumbo records one error per unclosed element at EOF, and each of those
  # carries a copy of the open-element tag stack, so an N-deep unclosed
  # document costs N^2 pointers: measured, 20 000 unclosed <div>s produced
  # 400 040 000 stack entries and 3.2 GB of allocations with the cap off, and
  # the input is only 100 KB. The default cap is what keeps that finite, so
  # this test pins both halves: the default is bounded, and a document deep
  # enough to have hit the quadratic is truncated by it.
  test "the default max_errors bounds the error list a deep document can produce" do
    {:ok, default} = Gumbo.Options.new([])
    assert default.max_errors > 0

    deep = "<!doctype html>" <> String.duplicate("<div>", 20_000)
    {:ok, output} = Gumbo.parse(deep)

    assert length(Gumbo.Output.errors(output)) == default.max_errors

    # -1 stays available, and is the documented way to ask for every error.
    assert {:ok, uncapped} = Gumbo.Options.new(max_errors: -1)
    assert uncapped.max_errors == -1
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

  test "each error type's fields survive the conversion" do
    cases = [
      {"<p>\xFF</p>", :utf8_invalid},
      {~s(<div a=1 a=2>), :duplicate_attr},
      {"<div><span>", :parser}
    ]

    for {html, type} <- cases do
      {:ok, output} = Gumbo.parse(html)

      error =
        output
        |> Gumbo.Output.errors()
        |> Enum.find(&(Gumbo.Error.type(&1) == type))

      assert error, "no #{type} error in #{inspect(html)}"
      assert is_binary(Gumbo.Error.message(error))
      assert Gumbo.Error.position(error).line >= 1
    end

    # The parser error carries the open tag stack, which is where the nested
    # extraction lives: a list of atoms inside a map inside the error vector.
    {:ok, output} = Gumbo.parse("<div><span>")

    # The premature-EOF error is the parser one with a non-empty stack; the
    # doctype error carries an empty one, exactly as the case above says.
    parser =
      output
      |> Gumbo.Output.errors()
      |> Enum.find(fn error ->
        Gumbo.Error.type(error) == :parser and
          match?(%{tag_stack: [_ | _]}, Gumbo.Error.parser_error(error))
      end)

    assert %{tag_stack: stack} = Gumbo.Error.parser_error(parser)
    assert stack != []
    assert Enum.all?(stack, &is_atom/1)
  end
end
