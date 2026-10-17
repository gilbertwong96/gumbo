defmodule Gumbo.DuplicateAttributeTest do
  # A duplicate attribute name is dropped with a parse error, and the tag buffer that held the
  # name is reset as part of dropping it. The pinned base did that reset inside
  # `add_duplicate_attr_error`, which returns before it when no error can be recorded — a capped
  # error list, and `max_errors: 0` is what asking for no errors at all produces — so the name
  # stayed in the buffer and the next attribute name was appended to it: `<p a=1 a b=2>` read
  # `[{"a", "1"}, {"ab", "2"}]`. Patch 0015 moves the reset to the caller, where Nokogiri's fork
  # has it, and the second shape below is one of the port's stored corpus bodies, whose own
  # reference parser reads the tree this asserts.
  use ExUnit.Case, async: true

  alias Gumbo.{Error, Output}

  defp attributes!(html, options \\ []) do
    {:ok, output} = Gumbo.parse_fragment(html, :body, options)

    output
    |> Output.fragment_nodes()
    |> Gumbo.materialize(detail: :tree)
    |> hd()
    |> Map.fetch!(:attributes)
  end

  test "with no errors recorded, a duplicate name is still dropped cleanly" do
    assert attributes!("<p a=1 a b=2>", max_errors: 0) == [{"a", "1"}, {"b", "2"}]
  end

  test "the default error handling reads the same tree" do
    assert attributes!("<p a=1 a b=2>") == [{"a", "1"}, {"b", "2"}]
  end

  # The name is dropped, not the rest of the tag: the shape a reader's corpus reported, where
  # the second `example.com` is the duplicate and `x.<` is the attribute that follows it.
  test "the corpus shape keeps the reference's four attributes with no errors recorded" do
    assert attributes!("<hs://example.com/x.https://example.com/x.</p>", max_errors: 0) == [
             {"example.com", ""},
             {"x.https:", ""},
             {"x.<", ""},
             {"p", ""}
           ]
  end

  # Moving the reset must not stop the name from reaching the error it is recorded in.
  test "the error still carries the duplicate's name and both indices" do
    {:ok, output} = Gumbo.parse_fragment("<p a=1 a b=2>", :body, max_errors: 100)

    assert [error] = Enum.filter(Output.errors(output), &(Error.type(&1) == :duplicate_attr))
    assert %{name: "a", original_index: 0, new_index: 1} = Error.duplicate_attr(error)
  end
end
