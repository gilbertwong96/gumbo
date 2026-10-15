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
end
