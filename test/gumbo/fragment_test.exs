defmodule Gumbo.FragmentTest do
  use ExUnit.Case, async: true

  test "in fragment mode root is gumbo's implied <html>, not the context element" do
    {:ok, output} = Gumbo.parse_fragment("<p>hi</p>", :div)
    root = Gumbo.Output.root(output)
    assert Gumbo.Node.tag(root) == :html
    assert Gumbo.Node.parse_flags(root) != []
    assert Enum.map(Gumbo.Output.fragment_nodes(output), &Gumbo.Node.tag/1) == [:p]
  end

  test "the context element does not appear in the tree" do
    {:ok, output} = Gumbo.parse_fragment("<li>a</li>", :ul)
    refute Enum.any?(Gumbo.Output.fragment_nodes(output), &(Gumbo.Node.tag(&1) == :ul))
  end

  test "an svg-namespace context is reachable from the three-argument form" do
    {:ok, output} = Gumbo.parse_fragment("<circle/>", :svg, fragment_namespace: :svg)
    assert Gumbo.Output.fragment_nodes(output) != []
  end

  test "passing the fragment keys in opts alongside the positional argument is an error" do
    assert {:error, {:conflicting_option, :fragment_context}} =
             Gumbo.parse_fragment("<p>", :div, fragment_context: :div)

    assert {:error, {:conflicting_option, :fragment_namespace}} =
             Gumbo.parse_fragment("<p>", :div, fragment_namespace: :svg)
  end

  test "table context applies the in-table rules" do
    {:ok, output} = Gumbo.parse_fragment("<tr><td>x</td></tr>", :table)
    assert Enum.map(Gumbo.Output.fragment_nodes(output), &Gumbo.Node.tag/1) != []
  end

  test "table context implies a tbody and puts the row inside it" do
    {:ok, output} = Gumbo.parse_fragment("<tr><td>x</td></tr>", :table)
    assert Enum.map(Gumbo.Output.fragment_nodes(output), &Gumbo.Node.tag/1) == [:tbody]
    [tbody] = Gumbo.Output.fragment_nodes(output)
    assert Enum.map(Gumbo.Node.children(tbody), &Gumbo.Node.tag/1) == [:tr]
  end

  test "template context uses the template insertion modes, so a row is not wrapped" do
    {:ok, output} = Gumbo.parse_fragment("<tr><td>x</td></tr>", :template)
    assert Enum.map(Gumbo.Output.fragment_nodes(output), &Gumbo.Node.tag/1) == [:tr]
  end

  test "rcdata contexts tokenize markup as text" do
    for context <- [:title, :textarea] do
      {:ok, output} = Gumbo.parse_fragment("<b>x</b>", context)
      [node] = Gumbo.Output.fragment_nodes(output)
      assert Gumbo.Node.type(node) == :text
      assert Gumbo.Node.text(node) == "<b>x</b>"
    end
  end

  test "raw text and script data contexts tokenize markup as text" do
    for context <- [:script, :style] do
      {:ok, output} = Gumbo.parse_fragment("<b>x</b>", context)
      [node] = Gumbo.Output.fragment_nodes(output)
      assert Gumbo.Node.type(node) == :text
      assert Gumbo.Node.text(node) == "<b>x</b>"
    end
  end

  test "plaintext context switches the tokenizer to the plaintext state" do
    {:ok, output} = Gumbo.parse_fragment("<b>x</b>", :plaintext)
    [node] = Gumbo.Output.fragment_nodes(output)
    assert Gumbo.Node.type(node) == :text
    assert Gumbo.Node.text(node) == "<b>x</b>"
  end

  test "the svg-namespace context puts children in the svg namespace" do
    {:ok, output} = Gumbo.parse_fragment("<circle/>", :svg, fragment_namespace: :svg)
    [node] = Gumbo.Output.fragment_nodes(output)
    assert Gumbo.Node.namespace(node) == :svg
    assert Gumbo.Node.tag(node) == :unknown
    assert Gumbo.Node.tag_name(node) == "circle"
  end

  test "without a namespace the svg context stays in the html namespace" do
    {:ok, output} = Gumbo.parse_fragment("<circle/>", :svg)
    [node] = Gumbo.Output.fragment_nodes(output)
    assert Gumbo.Node.namespace(node) == :html
  end

  test "a math context agrees with the mathml namespace" do
    {:ok, output} =
      Gumbo.parse_fragment("<mrow><mi>x</mi></mrow>", :math, fragment_namespace: :mathml)

    assert Enum.map(Gumbo.Output.fragment_nodes(output), &Gumbo.Node.namespace/1) == [
             :mathml
           ]
  end

  test "fragment_namespace conflicts only when it disagrees with the context's implied namespace" do
    assert {:ok, _} = Gumbo.parse_fragment("<p>", :div, fragment_namespace: :html)
    assert {:ok, _} = Gumbo.parse_fragment("<mrow/>", :math, fragment_namespace: :mathml)

    assert {:error, {:conflicting_option, :fragment_namespace}} =
             Gumbo.parse_fragment("<p>", :math, fragment_namespace: :html)

    assert {:error, {:conflicting_option, :fragment_namespace}} =
             Gumbo.parse_fragment("<circle/>", :svg, fragment_namespace: :mathml)
  end

  test "a context that is not a gumbo tag is rejected" do
    assert {:error, {:invalid_option, :fragment_context, :circle}} =
             Gumbo.parse_fragment("<circle/>", :circle)
  end

  test "other options pass through to the parse" do
    {:ok, output} = Gumbo.parse_fragment("<p>", :div, max_errors: 0)
    options = Gumbo.Output.options(output)
    assert options.max_errors == 0
    assert options.fragment_context == :div
    assert options.fragment_namespace == :html
  end

  test "parse_fragment!/3 raises ArgumentError with the reason" do
    assert_raise ArgumentError, ~r/conflicting_option/, fn ->
      Gumbo.parse_fragment!("<p>", :div, fragment_context: :div)
    end

    assert_raise ArgumentError, ~r/invalid_option/, fn ->
      Gumbo.parse_fragment!("<p>", :div, nope: 1)
    end
  end

  test "parse_fragment!/3 returns the output on success" do
    output = Gumbo.parse_fragment!("<p>hi</p>", :div)
    assert Enum.map(Gumbo.Output.fragment_nodes(output), &Gumbo.Node.tag/1) == [:p]
  end

  test "fragment_nodes/1 is the root's children, fragment mode or not" do
    {:ok, output} = Gumbo.parse("<!doctype html><p>hi</p>")
    assert Gumbo.Output.fragment_nodes(output) == Gumbo.Node.children(Gumbo.Output.root(output))
  end
end
