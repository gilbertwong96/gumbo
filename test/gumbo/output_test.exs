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

  test "document/1 and root/1 are distinct: index 0 is the document, index 1 the root" do
    assert {:ok, output} = Gumbo.parse("<p>")
    document = Output.document(output)
    root = Output.root(output)

    refute document == root
    assert document.index == 0
    assert root.index == 1
  end

  test "node_count/1 is cached and positive" do
    assert {:ok, output} = Gumbo.parse("<p>hello</p>")
    node_count = Output.node_count(output)

    assert is_integer(node_count)
    assert node_count > 0
    assert Output.node_count(output) == node_count
  end
end
