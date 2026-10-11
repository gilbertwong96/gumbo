defmodule Gumbo.OutputTest do
  use ExUnit.Case, async: true

  alias Gumbo.Output

  test "input/1 round-trips the exact bytes, including invalid UTF-8" do
    html = <<0x3C, 0x70, 0x3E, 0xFF, 0xFE, 0x3C, 0x2F, 0x70, 0x3E>>
    assert {:ok, output} = Gumbo.parse(html)
    assert Output.input(output) == html
  end

  test "input/1 round-trips the empty binary" do
    assert {:ok, output} = Gumbo.parse("")
    assert Output.input(output) == ""
  end

  test "options/1 reflects what was passed, dirty policy included" do
    opts = [tab_stop: 2, stop_on_first_error: true, max_errors: 3, dirty: false]
    assert {:ok, output} = Gumbo.parse("<p>", opts)

    assert Output.options(output) == %Gumbo.Options{
             tab_stop: 2,
             stop_on_first_error: true,
             max_errors: 3,
             dirty: false
           }
  end

  test "options/1 returns the defaults when none were passed" do
    assert {:ok, output} = Gumbo.parse("<p>")
    assert Output.options(output) == %Gumbo.Options{}
  end

  test "document/1 and root/1 are distinct: index 0 is the document" do
    assert {:ok, output} = Gumbo.parse("<p>")
    document = Output.document(output)
    root = Output.root(output)

    refute document == root
    assert document.index == 0
    assert root.index == 1
  end

  test "root/1 is the <html> element even when a comment precedes it" do
    # A comment before <html> is a document child and occupies table index
    # 1, so the root index must be resolved by pointer, never assumed.
    for html <- ["<!--c--><p>x</p>", ~s(<?xml version="1.0"?><p>x</p>)] do
      assert {:ok, output} = Gumbo.parse(html)
      root = Output.root(output)
      assert Gumbo.Node.type(root) == :element
      assert Gumbo.Node.tag(root) == :html
    end
  end

  test "a comment before <html> is a document child, not the root" do
    assert {:ok, output} = Gumbo.parse("<!--c--><p>x</p>")
    document = Output.document(output)
    assert document.index == 0

    [comment, html] = Gumbo.Node.children(document)
    assert Gumbo.Node.type(comment) == :comment
    assert Gumbo.Node.tag(html) == :html
    assert Output.root(output).index == html.index
  end

  test "root/1 is nil when stop_on_first_error halts before any element" do
    html = String.duplicate(~s(<div title=>), 50)
    assert {:ok, output} = Gumbo.parse(html, stop_on_first_error: true)

    assert Output.node_count(output) == 1
    assert Output.root(output) == nil
    assert Output.fragment_nodes(output) == []
    assert Output.errors(output) != []
  end

  test "node_count/1 is cached and positive" do
    assert {:ok, output} = Gumbo.parse("<p>hello</p>")
    node_count = Output.node_count(output)

    assert is_integer(node_count)
    assert node_count > 0
    assert Output.node_count(output) == node_count
  end

  test "the accessors raise ArgumentError on a forged resource" do
    forged = %Gumbo.Output{resource: self(), node_count: 0}

    assert_raise ArgumentError, fn -> Output.document(forged) end
    assert_raise ArgumentError, fn -> Output.root(forged) end
    assert_raise ArgumentError, fn -> Output.errors(forged) end
    assert_raise ArgumentError, fn -> Output.input(forged) end
    assert_raise ArgumentError, fn -> Output.options(forged) end
    assert_raise ArgumentError, fn -> Output.fragment_nodes(forged) end

    # node_count/1 reads only the cached field, so it does not raise.
    assert Output.node_count(forged) == 0
  end

  test "the accessors raise ArgumentError on a stale resource" do
    # A reference to a collected tree is still a reference: the NIF answers
    # {:error, :invalid_handle}, and errors/1 must raise rather than feed
    # that tuple to Enum.map as a protocol error.
    stale = %Gumbo.Output{resource: make_ref(), node_count: 0}

    assert_raise ArgumentError, fn -> Output.document(stale) end
    assert_raise ArgumentError, fn -> Output.root(stale) end
    assert_raise ArgumentError, fn -> Output.errors(stale) end
  end
end
