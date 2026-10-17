defmodule Gumbo.SelectScopeTest do
  # This branch parses a `select` the way Nokogiri's gumbo does: 0013 restores the "in select"
  # insertion mode the current spec removed, and inside that mode a token that is not an
  # `option`, an `optgroup`, an `hr`, a `script`/`template`, a nested `select` or one of the two
  # closing tags is a parse error and is ignored. So an element written inside a select is
  # dropped and its text merges with its neighbours, and an end tag written inside one cannot
  # reach the element above it.
  #
  # main holds the spec side of these five shapes — the same bytes insert the element or close
  # the `p` the in-body rule inserts there — and NOKOGIRI-COMPAT.md is why the branch exists.
  # `select_in_select_test.exs` holds the mode's own edges; the trees below are two corpus cases
  # the port reported plus their three neighbours.
  use ExUnit.Case, async: true

  alias Gumbo.Output

  defp content!(html) do
    {:ok, output} = Gumbo.parse_fragment(html, :body)
    output |> Output.fragment_nodes() |> Gumbo.materialize(detail: :content)
  end

  # The mode ignores the end tag, so it reaches neither the outer `p` (what the pinned base did)
  # nor an empty `p` inserted inside the select (what main does): the select's contents are one
  # text node.
  test "an end tag p inside a select changes nothing" do
    assert [%{type: :element, tag: :p, children: [select]}] =
             content!("<p><select>https://example.com/&lt;b</p>/p>")

    assert %{type: :element, tag: :select, children: [%{type: :text, text: text}]} = select
    assert text == "https://example.com/<b/p>"
  end

  test "the same holds with no outer p to find" do
    assert [%{type: :element, tag: :select, children: children}] = content!("<select>b</p>c")
    assert [%{type: :text, text: "bc"}] = children
  end

  # `source` is not a token the mode acts on, so it is dropped and only its text remains: this
  # is the second shape of the issue the corpus reported, and the one main keeps the element for.
  test "a source start tag inside a select is dropped" do
    assert [%{type: :element, tag: :select, children: children}] =
             content!(~s(<select><source id="i">tail</select>))

    assert [%{type: :text, text: "tail"}] = children
  end

  # `</marquee>` is ignored too, so the select stays where it is and what follows the end tag is
  # written into the select. main's parser reaches past the select, finds the marquee above it,
  # and pops both.
  test "an end tag marquee inside a select does not reach a marquee above it" do
    assert [
             %{
               type: :element,
               tag: :marquee,
               children: [%{type: :element, tag: :select, children: select_children}]
             }
           ] = content!("<marquee><select></marquee><b>x")

    assert [%{type: :text, text: "x"}] = select_children
  end

  # The corpus shape: a textarea before the center, the select inside the center, and both an
  # end tag center and an end tag marquee that the mode ignores.
  test "the same holds with the select nested deeper, as the corpus had it" do
    assert [%{type: :element, tag: :marquee, children: children}] =
             content!("<marquee><textarea></textarea><center><select></center></marquee><b>x")

    assert [
             %{type: :element, tag: :textarea, children: []},
             %{type: :element, tag: :center, children: center_children}
           ] = children

    assert [%{type: :element, tag: :select, children: [%{type: :text, text: "x"}]}] =
             center_children
  end
end
