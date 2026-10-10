defmodule Gumbo.StackTest do
  use ExUnit.Case, async: false
  @moduletag :small_stack

  alias Gumbo.Test.HTML

  defp assert_survives_death(build) do
    # Parsed in a helper so the reference leaves scope before the GC below;
    # rebinding to nil here would trigger an unused-variable warning.
    assert_parses(build.())

    :erlang.garbage_collect()

    # Reached only if the destructor did not take the VM down.
    assert {:ok, again} = Gumbo.parse("<p>after</p>")
    assert Gumbo.Output.node_count(again) > 0
  end

  defp assert_parses(html) do
    {:ok, output} = Gumbo.parse(html)
    assert Gumbo.Output.node_count(output) > 0
  end

  test "a 20k-deep span document parses and, critically, tears down" do
    html = HTML.nested("span", 20_000)
    # must take the dirty scheduler path
    assert byte_size(html) > 20_480
    assert_survives_death(fn -> html end)
  end

  test "a 20k-deep document walks with descendants/1 and still tears down" do
    # The walk is one children/1 NIF per node on the Elixir side, so it
    # exercises the node accessors at depth with no materialize in sight;
    # teardown after the walk is the assertion that matters.
    assert_walks_and_survives(fn -> HTML.nested("span", 20_000) end)
  end

  defp assert_walks_and_survives(build) do
    {:ok, output} = Gumbo.parse(build.())
    assert length(output |> Gumbo.Output.document() |> Gumbo.Node.descendants()) >= 20_002

    :erlang.garbage_collect()
    assert {:ok, again} = Gumbo.parse("<p>after</p>")
    assert Gumbo.Output.node_count(again) > 0
  end

  test "an 80k-deep table document tears down" do
    assert_survives_death(fn ->
      String.duplicate("<table><tr><td>", 20_000) <>
        String.duplicate("</td></tr></table>", 20_000)
    end)
  end

  test "the destructor survives running in a batch" do
    # Parsed in a helper so the list of handles leaves scope before the GC
    # below; rebinding to nil here would trigger an unused-variable warning.
    assert_parses_batch()

    :erlang.garbage_collect()
    assert {:ok, _} = Gumbo.parse("<p>after</p>")
  end

  defp assert_parses_batch do
    outputs = for _ <- 1..200, do: elem(Gumbo.parse(HTML.nested("template", 5_000)), 1)
    assert length(outputs) == 200
  end
end
