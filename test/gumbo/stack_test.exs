defmodule Gumbo.StackTest do
  use ExUnit.Case, async: false
  @moduletag :small_stack

  alias Gumbo.Test.HTML

  # The shape matrix from the design's Testing section: each shape is
  # generated wrapped in <!doctype html><html><body>…</body></html> — the
  # wrapper the expected depths were measured against — then parsed, its node
  # count and measured tree depth asserted, materialized at :full, walked
  # with descendants/1, and dropped; the GC below each case is where
  # teardown runs, on the small dirty-scheduler stack this suite is run
  # under. Depth is measured, not assumed: <a> and <colgroup> do not nest,
  # and a test that thought they did would be wrong about the parser.
  defp assert_shape(build, expected_count, expected_depth) do
    output = Gumbo.parse!(build.())
    document = Gumbo.Output.document(output)

    assert Gumbo.Output.node_count(output) == expected_count
    assert HTML.depth(document) == expected_depth

    assert %{document: _, root: root, errors: _} = Gumbo.materialize(output)
    assert HTML.materialized_depth(root) == expected_depth - 1

    # descendants/1 includes the node itself, so the document's walk visits
    # every node in the table
    assert length(Gumbo.Node.descendants(document)) == expected_count
  end

  test "shape matrix: nested <span>" do
    assert_shape(fn -> HTML.wrapped(HTML.nested("span", 20_000)) end, 20_004, 20_002)
    :erlang.garbage_collect()
  end

  test "shape matrix: nested <div>" do
    assert_shape(fn -> HTML.wrapped(HTML.nested("div", 20_000)) end, 20_004, 20_002)
    :erlang.garbage_collect()
  end

  test "shape matrix: nested <b>" do
    assert_shape(fn -> HTML.wrapped(HTML.nested("b", 20_000)) end, 20_004, 20_002)
    :erlang.garbage_collect()
  end

  test "shape matrix: nested <a> does not nest" do
    assert_shape(fn -> HTML.wrapped(HTML.nested("a", 20_000)) end, 20_004, 3)
    :erlang.garbage_collect()
  end

  test "shape matrix: nested <svg>" do
    assert_shape(fn -> HTML.wrapped(HTML.nested("svg", 20_000)) end, 20_004, 20_002)
    :erlang.garbage_collect()
  end

  test "shape matrix: nested <table><tr><td>" do
    table =
      String.duplicate("<table><tr><td>", 20_000) <>
        String.duplicate("</td></tr></table>", 20_000)

    assert_shape(fn -> HTML.wrapped(table) end, 80_004, 80_002)
    :erlang.garbage_collect()
  end

  test "shape matrix: nested <template>" do
    assert_shape(fn -> HTML.wrapped(HTML.nested("template", 20_000)) end, 20_004, 20_002)
    :erlang.garbage_collect()
  end

  test "shape matrix: nested <template> inside <select><selectedcontent><option>" do
    html =
      "<select><selectedcontent><option>" <>
        HTML.nested("template", 20_000) <> "</option></selectedcontent></select>"

    assert_shape(fn -> HTML.wrapped(html) end, 20_007, 20_005)
    :erlang.garbage_collect()
  end

  test "shape matrix: nested <colgroup> does not nest" do
    assert_shape(fn -> HTML.wrapped(HTML.nested("colgroup", 20_000)) end, 4, 2)
    :erlang.garbage_collect()
  end

  test "shape matrix: nested <frameset>" do
    assert_shape(fn -> HTML.wrapped(HTML.nested("frameset", 20_000)) end, 4, 2)
    :erlang.garbage_collect()
  end

  # Deliberately NOT HTML.wrapped/1. The wrapper's explicit <body> start tag
  # reaches handle_in_body's body branch, which clears frameset_ok, so the
  # <frameset> is dropped and the body survives — that is why the row above
  # measures depth 2 and never touches the destroy below. An *implicit* body
  # leaves frameset_ok true, so the <frameset> start tag reaches the branch
  # that pops the open elements and calls destroy_node on the body node,
  # during the parse, at input depth. The divs are what makes that subtree
  # deep; the assertion that the tree is 4 nodes deep 2 is the evidence the
  # body was really destroyed, and surviving to assert it is the evidence the
  # parse stayed inside its stack.
  test "shape matrix: nested <div> followed by a <frameset> destroys a deep body during parse" do
    html = "<!doctype html>" <> String.duplicate("<div>", 20_000) <> "<frameset>"

    assert_shape(fn -> html end, 4, 2)

    # Surviving that is the stack evidence. The shape is the evidence the branch
    # really ran, rather than the frameset being dropped and the body kept — the
    # two outcomes agree on 4 nodes and depth 2, so the count alone cannot tell
    # them apart. html's children are [head, frameset]: the body the deep divs
    # were built under is gone, destroyed during the parse.
    tags =
      html
      |> Gumbo.parse!()
      |> Gumbo.Output.root()
      |> Gumbo.Node.children()
      |> Enum.map(&Gumbo.Node.tag/1)

    assert tags == [:head, :frameset]

    :erlang.garbage_collect()
  end

  test "shape matrix: <select><selectedcontent> with 50 options of 20 000 spans" do
    select =
      "<select><selectedcontent>" <>
        Enum.map_join(1..50, "", fn _ ->
          "<option>" <> HTML.nested("span", 20_000) <> "</option>"
        end) <>
        "</selectedcontent></select>"

    assert_shape(fn -> HTML.wrapped(select) end, 1_000_056, 20_005)
    :erlang.garbage_collect()
  end

  test "shape matrix: 200 000 siblings" do
    assert_shape(fn -> HTML.wrapped(String.duplicate("<p>", 200_000)) end, 200_004, 3)
    :erlang.garbage_collect()
  end

  test "the destructor survives running in a batch" do
    # Parsed in a helper so the list of handles leaves scope before the GC
    # below; rebinding to nil here would trigger an unused-variable warning.
    assert_parses_batch()

    :erlang.garbage_collect()
    assert {:ok, _} = Gumbo.parse("<p>after</p>")
  end

  defp assert_parses_batch do
    batch = 200
    outputs = for _ <- 1..batch, do: elem(Gumbo.parse(HTML.nested("template", 5_000)), 1)
    assert length(outputs) == batch
  end
end
