defmodule Gumbo.ControlCharactersTest do
  use ExUnit.Case, async: true

  # The pinned parser replaces the input-stream characters the spec calls parse
  # errors — controls and noncharacters — with U+FFFD, and reports every one of
  # them as `:utf8_invalid`. The spec keeps the character and only calls it a
  # parse error, and Nokogiri's gumbo (an internal fork of lua-gumbo's) keeps it
  # and records what it is: `GUMBO_ERR_CONTROL_CHARACTER_IN_INPUT_STREAM` or
  # `GUMBO_ERR_NONCHARACTER_IN_INPUT_STREAM`. Reported as gilbertwong96/gumbo#4.
  #
  # What stays as it was: bytes that are not valid UTF-8 at all, which the spec
  # and the pin both replace (`:<invalid>` here is the DFA's reject path), and
  # character references, which the pin already keeps.
  #
  # `codepoint/1` is asserted too: the pin derived it from the raw bytes under
  # the cursor, so a multi-byte character reported its bytes rather than its code
  # point — 49797 for U+0085, 15710096 for U+FDD0.

  defp parsed(body) do
    {:ok, output} = Gumbo.parse_fragment(body, :body)
    output
  end

  defp text(output) do
    output
    |> Gumbo.Output.fragment_nodes()
    |> Gumbo.materialize(detail: :content)
    |> hd()
    |> Map.fetch!(:children)
    |> Enum.map(& &1.text)
    |> hd()
  end

  defp errors(output) do
    output
    |> Gumbo.Output.errors()
    |> Enum.map(&{Gumbo.Error.type(&1), Gumbo.Error.codepoint(&1)})
  end

  defp node_text(output) do
    output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> List.last() |> Gumbo.Node.text()
  end

  test "a control character in the input stream is kept, and named" do
    body = <<"<p>bell", 7, " esc", 27, " del", 127, " c1", 0xC2, 0x85, "</p>">>
    output = parsed(body)

    assert text(output) == <<"bell", 7, " esc", 27, " del", 127, " c1", 0xC2, 0x85>>
    assert node_text(output) == <<"bell", 7, " esc", 27, " del", 127, " c1", 0xC2, 0x85>>

    assert errors(output) == [
             {:control_character_in_input_stream, 7},
             {:control_character_in_input_stream, 27},
             {:control_character_in_input_stream, 127},
             {:control_character_in_input_stream, 0x85}
           ]
  end

  test "a noncharacter in the input stream is kept, and named" do
    body = <<"<p>", 0xEF, 0xB7, 0x90, "</p>">>
    output = parsed(body)

    assert text(output) == <<0xEF, 0xB7, 0x90>>
    assert errors(output) == [{:noncharacter_in_input_stream, 0xFDD0}]
  end

  test "whitespace the spec allows is not an error" do
    output = parsed("<p>\t\n</p>")

    assert text(output) == "\t\n"
    assert errors(output) == []
  end

  test "bytes that are not UTF-8 at all are still replaced" do
    output = parsed(<<"<p>", 0xFF, "</p>">>)

    assert text(output) == "\uFFFD"
    assert errors(output) == [{:utf8_invalid, 0xFF}]
  end

  test "a character reference keeps the byte it always kept" do
    output = parsed("<p>&#7;</p>")

    assert text(output) == "\a"
    assert errors(output) == [{:numeric_char_ref_invalid, 7}]
  end
end
