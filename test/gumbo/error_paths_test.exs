defmodule Gumbo.ErrorPathsTest do
  use ExUnit.Case, async: true

  # The entry points' error contract, which the return-convention change runs straight through: an
  # extractor now reports a failure by returning 0 rather than by handing back a term, so these cases
  # are the evidence that a 0 is still turned into the documented answer. A 0 mistaken for success
  # would not crash here — it would answer a tuple or a map that is missing what the caller asked for,
  # which is why each family names its tuple and the last case counts the fields of a full map.

  @html ~s(<div class="a" id="b">x</div>)

  test "a forged handle answers the documented tuple" do
    # The handle-only entries answer :invalid_handle; the ones that also resolve a node answer
    # :invalid_node, which is what they have always answered and what a caller can act on.
    assert Gumbo.Native.output_document(self()) == {:error, :invalid_handle}
    assert Gumbo.Native.node_details(self(), 0) == {:error, :invalid_node}
  end

  test "an index outside the node table answers the documented tuple" do
    {:ok, output} = Gumbo.parse(@html)

    assert Gumbo.Native.node_details(output.resource, 9_999) ==
             {:error, :invalid_node}

    assert Gumbo.Native.attr_details(output.resource, 9_999, 0) ==
             {:error, :invalid_node}
  end

  test "an index that is not an integer answers the documented tuple" do
    {:ok, output} = Gumbo.parse(@html)

    assert Gumbo.Native.node_details(output.resource, :zero) ==
             {:error, :invalid_node}

    assert Gumbo.Native.attr_details(output.resource, :zero, 0) ==
             {:error, :invalid_node}
  end

  test "an attribute index outside the element answers the documented tuple" do
    {:ok, output} = Gumbo.parse(@html)
    div = element(output)
    indices = Gumbo.Native.node_attributes(output.resource, div.index)

    assert indices != [],
           "the div at node #{div.index} should carry attributes, got none"

    assert Gumbo.Native.attr_details(
             output.resource,
             div.index,
             Enum.max(indices) + 1
           ) == {:error, :invalid_attribute},
           "the attributes are at #{inspect(indices)} on node #{div.index}"

    # The document carries no attribute vector at all.
    assert Gumbo.Native.attr_details(output.resource, 0, 0) ==
             {:error, :invalid_attribute}
  end

  test "a successful extraction fills every field it promises" do
    {:ok, output} = Gumbo.parse(@html)
    div = element(output)
    [index | _] = Gumbo.Native.node_attributes(output.resource, div.index)

    details =
      case Gumbo.Native.attr_details(output.resource, div.index, index) do
        {:ok, map} ->
          map

        other ->
          flunk("attr_details(#{div.index}, #{index}) answered #{inspect(other)}")
      end

    assert details[:name] == "class"
    assert details[:value] == "a"
    assert details[:original_name] == "class"
    assert details[:original_value] == ~s("a")
    assert %Gumbo.Position{} = details[:name_start]
    assert %Gumbo.Position{} = details[:value_end]

    assert details |> Map.keys() |> length() == 9
  end

  defp element(output) do
    output
    |> Gumbo.Output.document()
    |> Gumbo.Node.descendants()
    |> Enum.find(&(Gumbo.Node.tag(&1) == :div))
  end
end
