defmodule Gumbo.Test.HTMLTest do
  use ExUnit.Case, async: true

  alias Gumbo.Test.HTML

  test "nested/2 and wrapped/1 produce the shapes the suite's expectations are written against" do
    assert HTML.nested("div", 3) == "<div><div><div></div></div></div>"
    assert HTML.wrapped("x") == "<!doctype html><html><body>x</body></html>"
    assert HTML.nested("div", 0) == ""
  end

  # depth/1 is the instrument the stack suite's assertions read. A wrong instrument makes a
  # passing stack test say nothing, so it is checked against a shape whose depth is countable
  # by hand — and against materialized_depth/1, which must agree with it.
  #
  # The counted shape: Gumbo.Output.root/1 is the <html> element (not the document node), its
  # children are the implied <head> and the <body>, and <head> is a leaf, so the longest path
  # from root is html → body → div → div → div: 4 edges, 3 below body, 0 below head.
  test "depth/1 counts edges from the node it is given" do
    {:ok, output} = Gumbo.parse(HTML.wrapped(HTML.nested("div", 3)))
    root = Gumbo.Output.root(output)
    [head, body] = Gumbo.Node.children(root)

    assert HTML.depth(root) == 4
    assert HTML.depth(head) == 0
    assert HTML.depth(body) == 3
  end

  test "materialized_depth/1 agrees with depth/1 on the same document" do
    {:ok, output} = Gumbo.parse(HTML.wrapped(HTML.nested("div", 3)))

    assert %{document: _, root: materialized, errors: _} =
             Gumbo.materialize(output, detail: :full)

    assert HTML.materialized_depth(materialized) == HTML.depth(Gumbo.Output.root(output))
  end
end
