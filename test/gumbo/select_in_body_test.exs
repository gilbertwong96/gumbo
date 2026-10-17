defmodule Gumbo.SelectInBodyTest do
  use ExUnit.Case, async: true

  alias Gumbo.Output

  defp content!(html) do
    {:ok, output} = Gumbo.parse_fragment(html, :body)
    output |> Output.fragment_nodes() |> Gumbo.materialize(detail: :content)
  end

  # whatwg/html#10548 removed the "in select" insertion mode, moved its rules into "in
  # body", and listed `select` among the "in scope" element types (patch 0007). These are
  # the shapes where that move is observable on its own: what closes a select, what a
  # select keeps, and what closes to it. Chrome gives every tree below on the same bytes,
  # except the last one, which the spec asks for and Chrome does not do yet.
  #
  # The shapes the move also covers inside a `table` or a `td` are the ones
  # `select_tree_construction_test.exs` compares with upstream's own file.

  # The rule names `input` alone. So an input written inside a select closes it — what
  # follows is outside — while `textarea` and `keygen`, which the removed mode named
  # alongside it, stay where they are written.
  test "an input inside a select closes it and is parsed again in body" do
    assert [
             %{type: :element, tag: :select, children: []},
             %{type: :element, tag: :input, children: []}
           ] = content!("<select><input></select>")
  end

  test "a textarea and a keygen inside a select stay inside it" do
    assert [%{type: :element, tag: :select, children: [textarea]}] =
             content!("<select><textarea>x</textarea></select>")

    assert %{type: :element, tag: :textarea, children: [%{type: :text, text: "x"}]} = textarea

    assert [%{type: :element, tag: :select, children: [keygen]}] =
             content!("<select><keygen></select>")

    assert %{type: :element, tag: :keygen, children: []} = keygen
  end

  # `hr`, `option` and `optgroup` are the three the rule inserts, and each closes what it
  # follows: an option closes an option, an optgroup closes an option and an optgroup, and
  # an hr closes either of them before it is inserted and immediately popped.
  test "an hr inside a select closes an open option and stays inside" do
    assert [%{type: :element, tag: :select, children: children}] =
             content!("<select><option>a<hr>b")

    assert [
             %{type: :element, tag: :option, children: [%{type: :text, text: "a"}]},
             %{type: :element, tag: :hr, children: []},
             %{type: :text, text: "b"}
           ] = children
  end

  test "an option and an optgroup close what they follow" do
    assert [%{type: :element, tag: :select, children: children}] =
             content!("<select><option>a<option>b<optgroup><option>c<hr>d")

    assert [
             %{type: :element, tag: :option, children: [%{type: :text, text: "a"}]},
             %{type: :element, tag: :option, children: [%{type: :text, text: "b"}]},
             %{type: :element, tag: :optgroup, children: [option_c]},
             %{type: :element, tag: :hr, children: []},
             %{type: :text, text: "d"}
           ] = children

    assert %{type: :element, tag: :option, children: [%{type: :text, text: "c"}]} = option_c
  end

  # An end tag inside a select closes to the select rather than to what its name matches,
  # so the text after it stays inside: `</option>` pops the open option, `</optgroup>`
  # pops one too, and `</select>` pops to the select, which puts what follows outside it.
  test "an end tag option or optgroup inside a select closes only its own element" do
    assert [%{type: :element, tag: :select, children: children}, %{type: :text, text: "d"}] =
             content!("<select><option>a</option>b</optgroup>c</select>d")

    assert [
             %{type: :element, tag: :option, children: [%{type: :text, text: "a"}]},
             %{type: :text, text: "bc"}
           ] = children
  end

  test "an end tag select inside a select closes it" do
    assert [
             %{type: :element, tag: :select, children: [option_a]},
             %{type: :text, text: "b"}
           ] = content!("<select><option>a</select>b")

    assert %{type: :element, tag: :option, children: [%{type: :text, text: "a"}]} = option_a
  end

  # The nested case is the one removal the removed mode kept: a `select` start tag inside
  # a select is a parse error, the token is ignored and the open select is popped, so the
  # text written after the token is a sibling of the select rather than inside it.
  test "a nested select closes the one it sits in" do
    assert [%{type: :element, tag: :select, children: []}, %{type: :text, text: "x"}] =
             content!("<select><select>x")

    assert [%{type: :element, tag: :select, children: [option_a]}, %{type: :text, text: "b"}] =
             content!("<select><option>a<select>b")

    assert %{type: :element, tag: :option, children: [%{type: :text, text: "a"}]} = option_a
  end

  test "a script and a template inside a select go to in head" do
    assert [%{type: :element, tag: :select, children: children}] =
             content!("<select><script>var a = 1;</script><template>x</template>y")

    assert [
             %{type: :element, tag: :script, children: [%{type: :text, text: "var a = 1;"}]},
             %{type: :template, children: [%{type: :text, text: "x"}]},
             %{type: :text, text: "y"}
           ] = children
  end

  # `option` in body reconstructs the active formatting elements, and a select is not a
  # marker, so the question is whether the open `b` above it is reconstructed inside the
  # select: it is not, because that element is still open on the stack.
  test "a formatting element above a select is not reconstructed inside it" do
    assert [%{type: :element, tag: :b, children: children}] = content!("<b><select><option>x")

    assert [%{type: :element, tag: :select, children: [option_x]}] = children
    assert %{type: :element, tag: :option, children: [%{type: :text, text: "x"}]} = option_x
  end

  # The two fragment cases the rule adds: a fragment whose context element is a select
  # parses its content with the in-body rules, so an element is inserted where the removed
  # mode dropped it — and an `input`, which the rule would otherwise pop the select for, is
  # ignored instead. The spec asks for both; Chrome inserts the input today.
  test "a fragment whose context is a select parses its content in body" do
    assert {:ok, output} = Gumbo.parse_fragment("<i>x", :select)

    assert [%{type: :element, tag: :i, children: [%{type: :text, text: "x"}]}] =
             output |> Output.fragment_nodes() |> Gumbo.materialize(detail: :content)

    assert {:ok, output} = Gumbo.parse_fragment("<input>", :select)
    assert [] = output |> Output.fragment_nodes() |> Gumbo.materialize(detail: :content)
  end
end
