defmodule Gumbo.InTableTextTest do
  # The spec gates the "in table" character rule on the current node: a character token goes
  # to "in table text" when the current node is `table`, `tbody`, `template`, `tfoot`, `thead`
  # or `tr`, and is otherwise handled by the "anything else" arm — parse error, foster
  # parenting on, the in-body rules, foster parenting off
  # (parsing.html#parsing-main-intable, fetched 2026-10-17). Patch 0012 adds that condition:
  # the pinned base took the first branch for every character token in the mode, whatever the
  # current node was.
  #
  # What the difference costs is a text-node split, and only that: a run that takes the
  # unguarded route is accumulated in "in table text" and flushed at the next token, so a token
  # the parser then ignores ends the run and the character after it opens a new node. The first
  # shape below is the one a Rails port's stored corpus reported (`<table><r>x</h>e`), out of
  # its 1,058 bodies: with the condition it reads `{"r", [], ["xe"]}`, and Nokogiri's gumbo —
  # which has the condition — reads the same.
  use ExUnit.Case, async: true

  alias Gumbo.{Error, Output}

  defp content!(html) do
    {:ok, output} = Gumbo.parse_fragment(html, :body)
    output |> Output.fragment_nodes() |> Gumbo.materialize(detail: :content)
  end

  defp parser_errors!(html) do
    {:ok, output} = Gumbo.parse_fragment(html, :body)

    output
    |> Output.errors()
    |> Enum.map(&Error.parser_error/1)
    |> Enum.reject(&is_nil/1)
  end

  # The current node here is the `r` element the table context foster parented out, not a
  # table element, so both characters belong to the in-body rule and share one node. The end
  # tag is ignored, which is what used to end the first run and split the text.
  test "text whose current node is not a table element keeps one node across an ignored token" do
    assert [
             %{
               type: :element,
               tag: :unknown,
               tag_name: "r",
               children: [%{type: :text, text: "xe"}]
             },
             %{type: :element, tag: :table}
           ] = content!("<table><r>x</h>e")
  end

  # With the current node a `tr`, the character does go through "in table text", and because it
  # is not ASCII whitespace the run is foster parented out of the table: the text stays, one
  # node, ahead of the table. The spec asks for a parse error per pending character here, which
  # is a separate gap in the pinned base — whatwg/html#4046 is the open question about it, and
  # Nokogiri's fork answers with one error per character. This patch changes no error, so the
  # test asserts the tree.
  test "text under a table element is foster parented out of it" do
    assert [%{type: :text, text: "x"}, %{type: :element, tag: :table, children: [tbody]}] =
             content!("<table><tr>x</tr></table>")

    assert %{type: :element, tag: :tbody, children: [%{type: :element, tag: :tr}]} = tbody
  end

  # Whitespace is not a parse error even in "in table text": it is inserted where it is written,
  # inside the table, and the mode change is invisible.
  test "whitespace under a table element stays inside it" do
    assert [%{type: :element, tag: :table, children: [%{type: :whitespace, text: "\t\n  "}]}] =
             content!("<table>\t\n  </table>")

    assert parser_errors!("<table>\t\n  </table>") == []
  end

  # A NULL is a character token too, so the condition names it as well — and the mode it lands
  # in has a rule of its own for it: parse error, ignore the token.
  test "a null under a table element is ignored in the mode, not inserted" do
    assert [%{type: :element, tag: :table, children: []}] = content!("<table>\0</table>")
    refute Enum.any?(parser_errors!("<table>\0</table>"), &(&1.input_type == :character))
  end
end
