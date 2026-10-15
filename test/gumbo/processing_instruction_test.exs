defmodule Gumbo.ProcessingInstructionTest do
  use ExUnit.Case, async: true

  alias Gumbo.{Node, Output}

  defp nodes!(html) do
    {:ok, output} = Gumbo.parse_fragment(html, :body)
    Output.fragment_nodes(output)
  end

  defp full!(html), do: Gumbo.materialize(nodes!(html), detail: :full)
  defp content!(html), do: Gumbo.materialize(nodes!(html), detail: :content)

  test "a processing instruction splits into the target and the data the spec names" do
    # The C library keeps one string, "target␣data"; the spec's PI has both, and
    # a browser reports them apart: `<?pi?>` is target "pi" with empty data.
    assert [pi] = full!("<?pi?>")
    assert pi.type == :processing_instruction
    assert pi.target == "pi"
    assert pi.data == ""
    assert pi.text == "pi "
  end

  test "a target keeps the hyphens, underscores and digits the spec allows" do
    assert [pi] = full!("<?a-b_c9?>")
    assert pi.target == "a-b_c9"
    assert pi.data == ""
  end

  test "whitespace between the target and the data is not part of the data" do
    # Three spaces, a tab and a newline all arrive as one separator.
    for html <- ["<?pi   x?>", "<?pi\tx?>", "<?pi\nx?>"] do
      assert [pi] = full!(html), "for #{inspect(html)}"
      assert {pi.target, pi.data} == {"pi", "x"}, "for #{inspect(html)}"
    end
  end

  test "the data keeps its own spacing" do
    assert [%{data: "echo 1; "}] = full!("<?php echo 1; ?>")
    assert [%{data: "x  y"}] = full!("<?pi x  y?>")
  end

  test "only a processing instruction carries a target and a data" do
    for {html, type} <- [
          {"<p>x</p><!--c-->", :element},
          {"<!--c-->", :comment},
          {"x", :text}
        ] do
      map = html |> full!() |> hd()
      assert map.type == type, "for #{inspect(html)}"
      assert map.target == nil, "for #{inspect(html)}"
      assert map.data == nil, "for #{inspect(html)}"
    end
  end

  test "a disallowed target is a comment, and a comment has no target of its own" do
    # `<?xml` is the disallowed target of the spec's PI rules: the whole run,
    # question mark included, is the comment's data.
    assert [comment] = full!(~s(<?xml version="1.0"?>))
    assert comment.type == :comment
    assert comment.text == ~s(?xml version="1.0"?)
    assert comment.target == nil
    assert comment.data == nil
  end

  test "detail: :content answers the same target and data as detail: :full" do
    assert [pi] = content!("<?php echo 1; ?>")
    assert pi.type == :processing_instruction
    assert pi.target == "php"
    assert pi.data == "echo 1; "
  end

  test "the lazy accessors agree with the materialized shapes" do
    [pi] = nodes!("<?pi x?>")
    assert Node.target(pi) == "pi"
    assert Node.data(pi) == "x"

    [comment] = nodes!("<!--c-->")
    assert Node.target(comment) == nil
    assert Node.data(comment) == nil
  end
end
