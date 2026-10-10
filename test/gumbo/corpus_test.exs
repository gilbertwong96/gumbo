defmodule Gumbo.CorpusTest do
  use ExUnit.Case, async: true

  alias Gumbo.{Node, Output}

  @fixtures Path.wildcard(Path.expand("../fixtures/*.html", __DIR__))

  for fixture <- @fixtures do
    @tag fixture: fixture
    test "structural invariants hold on #{Path.basename(fixture)}", %{fixture: fixture} do
      assert_invariants(fixture |> File.read!() |> Gumbo.parse!())
    end
  end

  test "the root is resolved by tag, not index, when a leading comment precedes <html>" do
    output = Gumbo.parse!("<!--c--><p>x</p>")
    document = Output.document(output)

    # node index 0 is the document node
    assert document.index == 0
    assert Node.type(document) == :document

    # the comment pushed the root off index 1
    assert [first | _] = Node.children(document)
    assert Node.type(first) == :comment

    root = Output.root(output)
    assert Node.tag(root) == :html
    assert root.index != 1
  end

  defp assert_invariants(output) do
    document = Output.document(output)

    # node index 0 is the document node, and the root is the <html> element
    assert document.index == 0
    assert Node.type(document) == :document

    root = Output.root(output)
    refute is_nil(root)
    assert Node.tag(root) == :html

    # every node's parent/1 agrees with the parent implied by the tree walk,
    # the preorder table index of a node is strictly less than that of any
    # of its descendants, and positions are monotonic within a node's
    # original_tag
    walk([{document, nil}], %{}, Output.input(output))

    # materialize/2 at :full and the lazy accessors agree on every node's
    # tag, type and attribute count
    assert_full_agreement(Gumbo.materialize(output), document)
  end

  defp walk([], _by_original_tag, _input), do: :ok

  defp walk([{node, expected_parent} | rest], by_original_tag, input) do
    assert Node.parent(node) == expected_parent

    children = Node.children(node)
    Enum.each(children, fn child -> assert child.index > node.index end)

    walk(
      Enum.map(children, &{&1, node}) ++ rest,
      record_position(node, by_original_tag, input),
      input
    )
  end

  # Within one original_tag value, positions must be monotonic in tree
  # order — a mis-mapped position field (zeros, end positions, swapped
  # components) breaks the sequence — and the position must map back to the
  # tag's own bytes in the input. Reconstruction of active formatting
  # elements can clone a tag with its source position, so the sequence is
  # non-decreasing, not strictly increasing. Parser-inserted elements have
  # an empty original_tag and no source position to pin.
  defp record_position(node, by_original_tag, input) do
    case Node.original_tag(node) do
      original_tag when original_tag not in [nil, ""] ->
        position = Node.position(node)
        assert :binary.part(input, position.offset, byte_size(original_tag)) == original_tag

        offsets = Map.get(by_original_tag, original_tag, [])
        assert offsets == [] or position.offset >= List.last(offsets)
        Map.put(by_original_tag, original_tag, offsets ++ [position.offset])

      _ ->
        by_original_tag
    end
  end

  defp assert_full_agreement(full, document) do
    do_agreement([{full.document, document}])
  end

  defp do_agreement([]), do: :ok

  defp do_agreement([{materialized, lazy} | rest]) do
    assert materialized.type == Node.type(lazy)
    assert materialized.tag == Node.tag(lazy)
    assert length(materialized.attributes) == length(Node.attributes(lazy))

    lazy_children = Node.children(lazy)
    assert length(materialized.children) == length(lazy_children)
    do_agreement(Enum.zip(materialized.children, lazy_children) ++ rest)
  end
end
