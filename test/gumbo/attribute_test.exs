defmodule Gumbo.AttributeTest do
  use ExUnit.Case, async: true

  alias Gumbo.{Attribute, Node, Output}

  defp parse!(html) do
    {:ok, output} = Gumbo.parse(html)
    output
  end

  defp descendants(output), do: output |> Output.root() |> Node.descendants()

  @details_keys ~w(namespace name value original_name original_value name_start name_end value_start value_end)a

  test "lookup is case-insensitive, matching gumbo_get_attribute" do
    {:ok, output} = Gumbo.parse(~s(<div class="a" ID="b">x</div>))

    div =
      Gumbo.Output.root(output)
      |> Gumbo.Node.descendants()
      |> Enum.find(&(Gumbo.Node.tag(&1) == :div))

    assert Gumbo.Attribute.value(Gumbo.Node.attribute(div, "class")) == "a"
    assert Gumbo.Attribute.value(Gumbo.Node.attribute(div, "id")) == "b"
    assert Gumbo.Attribute.value(Gumbo.Node.attribute(div, "ID")) == "b"
    assert Gumbo.Node.attribute(div, "missing") == nil
  end

  test "attribute_map/1 keys are gumbo's normalized names and the map is lossy" do
    {:ok, output} = Gumbo.parse(~s(<div CLASS="a" ID="b">x</div>))

    div =
      Gumbo.Output.root(output)
      |> Gumbo.Node.descendants()
      |> Enum.find(&(Gumbo.Node.tag(&1) == :div))

    assert Gumbo.Node.attribute_map(div) == %{"class" => "a", "id" => "b"}
  end

  test "a name containing a NUL byte is rejected rather than truncating the C string" do
    {:ok, output} = Gumbo.parse(~s(<div class="a">x</div>))

    div =
      Gumbo.Output.root(output)
      |> Gumbo.Node.descendants()
      |> Enum.find(&(Gumbo.Node.tag(&1) == :div))

    assert Gumbo.Node.attribute(div, "class\0junk") == nil
  end

  test "attribute/2 matches names longer than the stack buffer" do
    # Above the 256-byte stack buffer, so the lookup goes through the heap
    # fallback in node_attribute.
    name = String.duplicate("a", 300)
    output = parse!("<div #{name}=\"x\"></div>")
    div = descendants(output) |> Enum.find(&(Node.tag(&1) == :div))

    assert Gumbo.Attribute.value(Gumbo.Node.attribute(div, name)) == "x"
    assert Gumbo.Node.attribute(div, String.duplicate("a", 301)) == nil
  end

  test "foreign attribute namespaces survive" do
    {:ok, output} = Gumbo.parse("<svg><a xlink:href=\"#x\"></a></svg>")

    attrs =
      output
      |> Gumbo.Output.root()
      |> Gumbo.Node.descendants()
      |> Enum.flat_map(&Gumbo.Node.attributes/1)

    assert Enum.any?(attrs, &(Gumbo.Attribute.namespace(&1) == :xlink))
  end

  test "original_value keeps the surrounding quotes and value/1 does not" do
    {:ok, output} = Gumbo.parse(~s(<div class="a">x</div>))

    attr =
      output
      |> Gumbo.Output.root()
      |> Gumbo.Node.descendants()
      |> Enum.flat_map(&Gumbo.Node.attributes/1)
      |> hd()

    assert Gumbo.Attribute.value(attr) == "a"
    assert Gumbo.Attribute.original_value(attr) == ~s("a")
  end

  test "attributes/1 lists attributes in source order and attribute/2 returns structs" do
    output = parse!(~s(<div class="a" id="b">x</div>))
    div = descendants(output) |> Enum.find(&(Node.tag(&1) == :div))

    assert [class, id] = Node.attributes(div)
    assert %Gumbo.Attribute{node: ^div, index: 0} = class
    assert %Gumbo.Attribute{node: ^div, index: 1} = id
    assert Attribute.name(class) == "class"
    assert Attribute.name(id) == "id"
    assert Node.attribute(div, "CLASS") == class
  end

  test "attributes/1 is [] and attribute/2 nil off elements" do
    output = parse!("<p>x</p>")
    document = Output.document(output)
    text = descendants(output) |> Enum.find(&(Node.type(&1) == :text))

    assert Node.attributes(document) == []
    assert Node.attribute(document, "class") == nil
    assert Node.attribute_map(document) == %{}

    assert Node.attributes(text) == []
    assert Node.attribute(text, "x") == nil
    assert Node.attribute_map(text) == %{}
  end

  test "attribute/2 raises ArgumentError for a non-binary name on any node type" do
    output = parse!("<p>x</p>")
    document = Output.document(output)
    text = descendants(output) |> Enum.find(&(Node.type(&1) == :text))

    # The argument check comes before the element check: nil documents "off
    # elements", never a different failure mode for the same bad argument.
    assert_raise ArgumentError, fn -> Node.attribute(document, 123) end
    assert_raise ArgumentError, fn -> Node.attribute(text, 123) end
  end

  test "details/1 returns the same values the individual accessors return" do
    output = parse!(~s(<div class="a" data-x='b'>x</div>))
    div = descendants(output) |> Enum.find(&(Node.tag(&1) == :div))
    [class, data_x] = Node.attributes(div)

    assert {:ok, class_details} = Attribute.details(class)
    assert Enum.sort(Map.keys(class_details)) == Enum.sort(@details_keys)
    assert class_details.namespace == Attribute.namespace(class)
    assert class_details.name == Attribute.name(class)
    assert class_details.value == Attribute.value(class)
    assert class_details.original_name == Attribute.original_name(class)
    assert class_details.original_value == Attribute.original_value(class)
    assert class_details.name_start == Attribute.name_start(class)
    assert class_details.name_end == Attribute.name_end(class)
    assert class_details.value_start == Attribute.value_start(class)
    assert class_details.value_end == Attribute.value_end(class)

    assert Attribute.namespace(class) == :none
    assert Attribute.name(class) == "class"
    assert Attribute.value(class) == "a"
    assert Attribute.original_name(class) == "class"
    assert Attribute.original_value(class) == ~s("a")
    # Positions bracket the name and the value as written: the value span
    # includes the surrounding quotes (original_value does too).
    assert Attribute.name_start(class) == %Gumbo.Position{line: 1, column: 6, offset: 5}
    assert Attribute.name_end(class) == %Gumbo.Position{line: 1, column: 11, offset: 10}
    assert Attribute.value_start(class) == %Gumbo.Position{line: 1, column: 12, offset: 11}
    assert Attribute.value_end(class) == %Gumbo.Position{line: 1, column: 15, offset: 14}

    assert Attribute.name(data_x) == "data-x"
    assert Attribute.value(data_x) == "b"
    assert Attribute.original_value(data_x) == ~s('b')
  end

  test "a foreign attribute is renamed by the parser while original_name/1 keeps the source" do
    output = parse!(~s(<svg><a xlink:href="#x"></a></svg>))
    a = descendants(output) |> Enum.find(&(Node.tag(&1) == :a))
    [attr] = Node.attributes(a)

    assert Attribute.namespace(attr) == :xlink
    assert Attribute.name(attr) == "href"
    assert Attribute.original_name(attr) == "xlink:href"
    assert Attribute.original_value(attr) == ~s("#x")
    assert Attribute.value(attr) == "#x"
  end

  test "attribute_map/1 folds namespaces away and attributes/1 does not" do
    # Both attributes are named "href" after the parser adjusts foreign
    # attributes (one in the :none namespace, one in :xlink), so the map
    # keeps only one of them.
    output = parse!(~s(<svg><a href="x" xlink:href="y"></a></svg>))
    a = descendants(output) |> Enum.find(&(Node.tag(&1) == :a))

    attrs = Node.attributes(a)
    assert Enum.map(attrs, &Attribute.name/1) == ["href", "href"]
    assert Enum.map(attrs, &Attribute.namespace/1) == [:none, :xlink]
    assert Node.attribute_map(a) == %{"href" => "y"}
  end

  test "an out-of-range node or attribute index is an error, never a dereference" do
    {:ok, output} = Gumbo.parse(~s(<div class="a">x</div>))
    div = descendants(output) |> Enum.find(&(Node.tag(&1) == :div))

    forged_attribute = %Gumbo.Attribute{node: div, index: 10_000_000}
    assert {:error, :invalid_attribute} = Attribute.details(forged_attribute)
    assert_raise ArgumentError, fn -> Attribute.name(forged_attribute) end
    assert_raise ArgumentError, fn -> Attribute.value(forged_attribute) end

    forged_node = %Gumbo.Attribute{node: %Gumbo.Node{output: output, index: 10_000_000}, index: 0}
    assert {:error, :invalid_node} = Attribute.details(forged_node)
    assert_raise ArgumentError, fn -> Attribute.name(forged_node) end

    forged_element = %Gumbo.Node{output: output, index: 10_000_000}
    assert_raise ArgumentError, fn -> Node.attributes(forged_element) end
    assert_raise ArgumentError, fn -> Node.attribute(forged_element, "class") end
    assert_raise ArgumentError, fn -> Node.attribute_map(forged_element) end
  end
end
