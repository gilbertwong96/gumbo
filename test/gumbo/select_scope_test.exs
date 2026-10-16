defmodule Gumbo.SelectScopeTest do
  use ExUnit.Case, async: true

  alias Gumbo.Output

  defp content!(html) do
    {:ok, output} = Gumbo.parse_fragment(html, :body)
    output |> Output.fragment_nodes() |> Gumbo.materialize(detail: :content)
  end

  # The current spec has no "in select" insertion mode: whatwg/html#10548 removed
  # it, moved those rules into "in body", and lists `select` among the "in scope"
  # element types. So a `p` outside a `select` is not in button scope from inside
  # one, and the in-body end tag "p" rule inserts an empty `p` *inside* the
  # select and closes that. Chrome, on the same bytes, gives this tree.
  test "an end tag p inside a select closes the p it inserts there, not the outer one" do
    assert [%{type: :element, tag: :p, children: [select]}] =
             content!("<p><select>https://example.com/&lt;b</p>/p>")

    assert %{type: :element, tag: :select, children: children} = select

    assert [
             %{type: :text, text: "https://example.com/<b"},
             %{type: :element, tag: :p, children: []},
             %{type: :text, text: "/p>"}
           ] = children
  end

  test "the same holds with no outer p to find" do
    assert [%{type: :element, tag: :select, children: children}] = content!("<select>b</p>c")

    assert [
             %{type: :text, text: "b"},
             %{type: :element, tag: :p, children: []},
             %{type: :text, text: "c"}
           ] = children
  end

  # The relaxed rules leave `source` as an ordinary in-body start tag, so the
  # element is inserted and kept. This is the second shape of the issue, and it
  # is the current behaviour: the test records the decision that it stays.
  test "a source start tag inside a select is kept" do
    assert [%{type: :element, tag: :select, children: children}] =
             content!(~s(<select><source id="i">tail</select>))

    assert [%{type: :element, tag: :source}, %{type: :text, text: "tail"}] = children
  end

  # The spec's in-body end tag rule for `applet`, `marquee` and `object` asks for the
  # element in scope, and `select` is one of the boundaries that query stops at. The
  # pinned base asked in *table* scope, whose boundaries are only html, table and
  # template, so the select stopped nothing, the marquee above it was found, and the
  # token popped the select and everything under it. Chrome, on the same bytes, gives
  # these trees.
  test "an end tag marquee inside a select does not reach a marquee above it" do
    assert [%{type: :element, tag: :marquee, children: children}] =
             content!("<marquee><select></marquee><b>x")

    assert [%{type: :element, tag: :select, children: select_children}] = children

    assert [%{type: :element, tag: :b, children: [%{type: :text, text: "x"}]}] =
             select_children
  end

  # The corpus shape: a textarea before the center, the select inside the center, and
  # both an end tag center and an end tag marquee that can no longer see their target.
  test "the same holds with the select nested deeper, as the corpus had it" do
    assert [%{type: :element, tag: :marquee, children: children}] =
             content!("<marquee><textarea></textarea><center><select></center></marquee><b>x")

    assert [
             %{type: :element, tag: :textarea, children: []},
             %{type: :element, tag: :center, children: center_children}
           ] = children

    assert [%{type: :element, tag: :select, children: select_children}] = center_children

    assert [%{type: :element, tag: :b, children: [%{type: :text, text: "x"}]}] =
             select_children
  end
end
