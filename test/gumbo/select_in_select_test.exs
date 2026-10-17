defmodule Gumbo.SelectInSelectTest do
  # The "in select" insertion mode 0013 restores, tested where the branch exists for it: a
  # Rails port whose reference parses with Nokogiri's gumbo. main keeps the current spec, where
  # whatwg/html#10548 folded this mode's rules into "in body" and an element written inside a
  # select is kept; NOKOGIRI-COMPAT.md has the three generations side by side, the port's
  # 1,058-case corpus is what this branch is held to, and the rules themselves are upstream
  # 7811944's own code, restored.
  #
  # What the mode does, in one line: inside a select, only characters, comments, an `option`, an
  # `optgroup`, an `hr`, a `script`/`template` and the two closing tags are acted on; anything
  # else is a parse error and the token is ignored. `select_scope_test.exs` holds the shapes
  # where that matters for an end tag and for an element's text; this file holds the mode's own
  # edges, including the two that report its state — the enum members sit in the middle of the
  # enum, where Nokogiri's are, so an error's insertion mode is what would notice them moving.
  use ExUnit.Case, async: true

  alias Gumbo.{Error, Output}

  defp content!(html) do
    {:ok, output} = Gumbo.parse_fragment(html, :body)
    output |> Output.fragment_nodes() |> Gumbo.materialize(detail: :content)
  end

  defp modes(html) do
    {:ok, output} = Gumbo.parse(html)
    output |> Output.errors() |> Enum.map(&Error.parser_error(&1).insertion_mode)
  end

  test "an element written inside a select is dropped and its text merges with its neighbours" do
    assert [%{type: :element, tag: :div, children: [select]}] =
             content!("<div><select>a<i>b</i>c</select></div>")

    assert %{type: :element, tag: :select, children: [%{type: :text, text: "abc"}]} = select
  end

  # The mode's own tokens are the exception: an option, an optgroup and an hr are inserted, and
  # a second option closes the first, while an hr closes an open option and optgroup and lands
  # among the select's children, which is what a select holds in either generation.
  test "an option, an optgroup and an hr are inserted, and each closes what it follows" do
    assert [%{type: :element, tag: :select, children: children}] =
             content!("<select><option>a<option>b<optgroup><option>c<hr>d</select>")

    assert [
             %{type: :element, tag: :option, children: [%{type: :text, text: "a"}]},
             %{type: :element, tag: :option, children: [%{type: :text, text: "b"}]},
             %{
               type: :element,
               tag: :optgroup,
               children: [%{type: :element, tag: :option, children: [%{type: :text, text: "c"}]}]
             },
             %{type: :element, tag: :hr, children: []},
             %{type: :text, text: "d"}
           ] = children
  end

  # The one removal the mode keeps, and the shape the port's corpus had: the nested select closes
  # the outer one, so what follows its end tag is outside the select rather than inside it.
  test "a nested select closes the one it sits in" do
    assert [
             %{type: :element, tag: :select, children: []},
             %{type: :text, text: "xy"}
           ] = content!("<select><marquee><i><select>x</select>y")
  end

  # `<input>`, `<keygen>` and `<textarea>` pop to the select and are then processed again where
  # the mode left the parser: in body, which inserts the input.
  test "an input inside a select closes the select and is parsed again in body" do
    assert [
             %{type: :element, tag: :select, children: []},
             %{type: :element, tag: :input, children: []}
           ] = content!("<select><input></select>")
  end

  test "a script and a template go to in head, where they are inserted" do
    assert [%{type: :element, tag: :select, children: children}] =
             content!("<select><script>var a = 1;</script><template>x</template>y")

    assert [
             %{
               type: :element,
               tag: :script,
               children: [%{type: :text, text: "var a = 1;"}]
             },
             %{
               type: :template,
               tag: :template,
               children: [%{type: :text, text: "x"}]
             },
             %{type: :text, text: "y"}
           ] = children
  end

  # A table token takes the select with it and is processed again in the table modes, which is
  # the second mode this patch restores and the only way to reach it.
  test "a table token closes the select and is processed again in the table" do
    assert modes("<table><select>a</table>") == [
             :initial,
             :in_table,
             :in_select_in_table
           ]
  end

  # A fragment whose context element is a select starts in the mode, as it did before 7811944:
  # the context stands in for the last open element, so the restored `select` case answers for
  # it. The element is dropped here for the same reason it is dropped inside a select in a
  # document, and the error is reported in the mode.
  test "a fragment whose context is a select starts in the mode" do
    {:ok, output} = Gumbo.parse_fragment("<i>x", :select)

    assert [%{type: :text, text: "x"}] =
             output |> Output.fragment_nodes() |> Gumbo.materialize(detail: :content)

    assert [%{insertion_mode: :in_select}] =
             output |> Output.errors() |> Enum.map(&Error.parser_error(&1))
  end

  test "an error inside a select reports the mode it happened in" do
    assert :in_select in modes("<select><i>x</i></select>")
    assert :in_select in modes("<p><select>a</p>b")
  end
end
