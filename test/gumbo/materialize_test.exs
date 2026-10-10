defmodule Gumbo.MaterializeTest do
  use ExUnit.Case, async: true

  alias Gumbo.{Attribute, Error, Node, Output}

  test "detail: :full carries every field the lazy accessors return" do
    {:ok, output} = Gumbo.parse(~s(<div class="a" id="b">x<!--c--></div>))
    full = Gumbo.materialize(output)

    assert %{document: _, root: _, errors: _} = full
    assert full.document.type == :document
    # the document node's only child is the root <html> element
    assert full.document.children == [full.root]

    # The div is a child of the implied <body>, not of the root, so the
    # lookup walks the materialized children lists instead of assuming.
    div = find_tag(full.root, :div)
    assert div.type == :element
    assert div.namespace == :html
    assert div.tag_name == "div"
    assert is_list(div.parse_flags)
    assert %Gumbo.Position{} = div.start_position
    assert %Gumbo.Position{} = div.end_position
    # 0.14.1 keeps the whole start tag as written, attributes and '>' included
    assert div.original_tag == ~s(<div class="a" id="b">)
    assert div.original_end_tag == "</div>"

    assert [
             %{
               name: "class",
               value: "a",
               namespace: :none,
               original_value: ~s("a")
             }
             | _
           ] = div.attributes

    assert is_integer(div.index_within_parent)
    assert div.children |> Enum.map(& &1.type) |> Enum.member?(:text)
    assert div.children |> Enum.map(& &1.type) |> Enum.member?(:comment)
    assert div.text == nil

    # The materialized values agree with the lazy accessors on the same node.
    div_node =
      output
      |> Output.root()
      |> Node.descendants()
      |> Enum.find(&(Node.tag(&1) == :div))

    assert div.start_position == Node.position(div_node)
    assert div.end_position == Node.end_position(div_node)
    assert div.original_tag == Node.original_tag(div_node)
    assert div.original_end_tag == Node.original_end_tag(div_node)
    assert div.parse_flags == Node.parse_flags(div_node)
  end

  test "a comment before <html> does not displace the materialized root" do
    {:ok, output} = Gumbo.parse("<!--c--><p>x</p>")
    full = Gumbo.materialize(output)

    assert full.root[:type] == :element
    assert full.root[:tag] == :html
    assert [%{type: :comment}, %{tag: :html}] = full.document.children
  end

  test "a root-less output materializes with root: nil and its errors intact" do
    html = String.duplicate(~s(<div title=>), 50)
    assert {:ok, output} = Gumbo.parse(html, stop_on_first_error: true)

    full = Gumbo.materialize(output)
    assert full.root == nil
    assert full.document.type == :document
    assert full.document.children == []
    assert full.errors != []
  end

  test "detail: :full agrees with the lazy accessors field by field" do
    {:ok, output} =
      Gumbo.parse(
        ~s(<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">) <>
          ~s(<p class="a">x &amp; y<!--c--></p>)
      )

    # The walk covers the doctype-bearing document (the renamed-:name area),
    # the root and every element, the text node with its entity decoding,
    # and the comment, comparing every field against the same node through
    # the lazy surface.
    assert_full_agreement(Gumbo.materialize(output).document, Output.document(output))
  end

  test "detail: :content is a usable tree without source bookkeeping" do
    {:ok, output} = Gumbo.parse(~s(<div class="a">x</div>))
    content = Gumbo.materialize(output, detail: :content)

    div = find_tag(content.root, :div)
    assert div.attributes == %{"class" => "a"}
    assert div.children |> Enum.map(& &1.type) |> Enum.member?(:text)
    refute Map.has_key?(div, :start_position)
    refute Map.has_key?(div, :parse_flags)

    assert %{type: :document} = content.document
    assert %{type: :text, text: "x"} = List.last(div.children)
  end

  test "materializing a single node returns that node" do
    {:ok, output} = Gumbo.parse("<p>hi</p>")
    node = Output.root(output)

    assert %{type: :element, tag: :html} = Gumbo.materialize(node)

    assert %{type: :element, tag: :html, attributes: %{}, children: _} =
             Gumbo.materialize(node, detail: :content)
  end

  test "materializing a list and nil" do
    {:ok, output} = Gumbo.parse("<p>hi</p>")
    root = Output.root(output)

    assert [%{type: :element}, %{type: :element}] = Gumbo.materialize([root, root])
    assert Gumbo.materialize(nil) == nil
  end

  test "materializing a forged node returns {:error, :invalid_node}" do
    {:ok, output} = Gumbo.parse("<p>hi</p>")
    forged = %Gumbo.Node{output: output, index: 10_000_000}

    assert Gumbo.materialize(forged) == {:error, :invalid_node}
  end

  test "errors materialize as the maps Error.details/1 returns" do
    {:ok, output} = Gumbo.parse(~s(<div a=1 a=2></div>))
    [error | _] = Gumbo.materialize(output).errors
    assert error.type == :duplicate_attr

    error_node = output |> Output.errors() |> hd()
    assert {:ok, details} = Error.details(error_node)
    assert error == details
  end

  @tag :small_stack
  test "a deeply nested document materializes on the small stack" do
    {:ok, output} = Gumbo.parse(Gumbo.Test.HTML.nested("span", 20_000))
    assert tree_depth(Gumbo.materialize(output).root) > 10_000
  end

  test "invalid detail raises rather than guessing" do
    {:ok, output} = Gumbo.parse("<p>hi</p>")
    assert_raise ArgumentError, fn -> Gumbo.materialize(output, detail: :nope) end
  end

  # Depth-first over the materialized children lists, iterative so it is safe
  # on arbitrarily deep documents; [access] is what keeps it total on maps.
  defp find_tag(node, tag), do: walk([node], tag)
  defp walk([], _tag), do: nil

  defp walk([node | rest], tag) do
    if node[:tag] == tag do
      node
    else
      walk(Map.get(node, :children, []) ++ rest, tag)
    end
  end

  defp tree_depth(root), do: do_depth([{root, 0}], 0)

  defp do_depth([], best), do: best

  defp do_depth([{node, d} | rest], best) do
    do_depth(Enum.map(node[:children], &{&1, d + 1}) ++ rest, max(best, d))
  end

  # Compares a materialized :full node against its lazy counterpart, field
  # by field: the 17 scalar fields through details/1 (with the materialized
  # shape's two key renames mapped explicitly), the whole attribute list,
  # and the children lists recursively. Tail-recursive on the pair queue, so
  # the walk is iterative exactly like the helpers above.
  defp assert_full_agreement(materialized, lazy) do
    compare_pairs([{materialized, lazy}])
  end

  defp compare_pairs([]), do: :ok

  defp compare_pairs([{mat, lazy} | rest]) do
    {:ok, details} = Node.details(lazy)

    assert mat.type == details.type
    assert mat.index_within_parent == details.index_within_parent
    assert mat.parse_flags == details.parse_flags
    assert mat.start_position == details.position
    assert mat.has_doctype == details.has_doctype
    assert mat.name == details.doctype_name
    assert mat.public_identifier == details.public_identifier
    assert mat.system_identifier == details.system_identifier
    assert mat.quirks_mode == details.quirks_mode
    assert mat.tag == details.tag
    assert mat.tag_name == details.tag_name
    assert mat.namespace == details.namespace
    assert mat.original_tag == details.original_tag
    assert mat.original_end_tag == details.original_end_tag
    assert mat.end_position == details.end_position
    assert mat.text == details.text
    assert mat.original_text == details.original_text

    lazy_attributes =
      lazy
      |> Node.attributes()
      |> Enum.map(fn attribute ->
        {:ok, attribute_details} = Attribute.details(attribute)
        attribute_details
      end)

    assert mat.attributes == lazy_attributes

    lazy_children = Node.children(lazy)
    assert length(mat.children) == length(lazy_children)
    compare_pairs(Enum.zip(mat.children, lazy_children) ++ rest)
  end
end
