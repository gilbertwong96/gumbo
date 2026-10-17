defmodule Gumbo.FosterTextTest do
  # This branch splits foster-parented text the way Nokogiri's gumbo does: a run a table
  # context pushes out to the adjusted insertion location becomes a node of its own instead of
  # merging into whichever text node precedes it. Upstream 41a0f3e made it merge — the "insert a
  # character" algorithm asks for that — and Nokogiri's fork predates the change, so patch 0014
  # puts this branch back on the older side. Rendering cannot see the difference; a tree
  # comparison can, and so can anything acting per text node, an autolinker for instance.
  #
  # The first two shapes are upstream's own: before that commit `MisnestedTable2` in its
  # `tests/parser.cc` expected the three children below. The port's reference parser, which
  # vendors Nokogiri 1.19.4's unmodified gumbo sources, produces the same trees.
  use ExUnit.Case, async: true

  alias Gumbo.Output

  defp content!(html) do
    {:ok, output} = Gumbo.parse_fragment(html, :body)
    output |> Output.fragment_nodes() |> Gumbo.materialize(detail: :content)
  end

  test "a run foster parented out of a table is a node of its own" do
    assert [%{type: :element, tag: :div, children: children}] =
             content!("<div>a<table>b</table>")

    assert [
             %{type: :text, text: "a"},
             %{type: :text, text: "b"},
             %{type: :element, tag: :table, children: []}
           ] = children
  end

  test "upstream's misnested table keeps the children its pre-merge test expected" do
    assert [%{type: :element, tag: :table, children: [tbody]}] =
             content!("<table><td>Cell1<table><th>Cell2<tr>Cell3</table>")

    assert %{type: :element, tag: :tbody, children: [tr]} = tbody
    assert %{type: :element, tag: :tr, children: [td]} = tr

    assert %{type: :element, tag: :td, children: [cell1, cell3, inner]} = td
    assert %{type: :text, text: "Cell1"} = cell1
    assert %{type: :text, text: "Cell3"} = cell3
    assert %{type: :element, tag: :table} = inner
  end

  test "every foster parented run keeps its own node, before and after the table" do
    assert [%{type: :element, tag: :div, children: children}] =
             content!("<div>a<table>x<tr>y</table>z")

    assert [
             %{type: :text, text: "a"},
             %{type: :text, text: "x"},
             %{type: :text, text: "y"},
             %{type: :element, tag: :table},
             %{type: :text, text: "z"}
           ] = children
  end
end
