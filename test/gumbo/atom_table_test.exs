defmodule Gumbo.AtomTableTest do
  # The atom table is a global, fixed-size resource — 1 048 576 entries by default — and a VM that
  # exhausts it dies, rather than the process that filled it. Document input is untrusted, so nothing
  # that comes out of a document may be interned: a name stays a binary, and every unknown tag is the
  # single :unknown atom that gumbo's own enum resolves to.
  #
  # This file is the only thing that enforces that. The count it reads is global, so it is noisy: a
  # control that did not touch this library at all grew the table by 14 while measuring, which is why
  # the tolerance is 100 rather than 0. One leak per name is a thousand times larger than that and
  # cannot hide underneath it.
  use ExUnit.Case, async: false

  alias Gumbo.Node

  @names 1_000
  @tolerance 100

  test "the names and tags of a document are never interned" do
    warm_up()

    names = for i <- 1..@names, do: "custom-el-#{i}"
    html = Enum.map_join(names, fn name -> "<#{name} data-#{name}=\"v\">x</#{name}>" end)

    before = atom_count()
    {:ok, output} = Gumbo.parse(html)
    content = Gumbo.materialize(output, detail: :content)
    _full = Gumbo.materialize(output, detail: :full)
    nodes = Node.descendants(Gumbo.Output.root(output))

    # The paths were really exercised. Every element is the same unknown tag — one atom for all
    # thousand names — and each name came back a binary, which is what makes that possible.
    unknown = Enum.filter(nodes, &(Node.tag(&1) == :unknown))
    assert length(unknown) == @names
    assert Enum.all?(unknown, &is_binary(Node.tag_name(&1)))

    body = Enum.find(content.root.children, &(&1[:tag] == :body))
    first = Enum.find(body[:children], &(&1[:tag] == :unknown))
    assert is_binary(first[:tag_name])

    assert atom_count() - before < @tolerance,
           "#{@names} names from one document grew the atom table by #{atom_count() - before}: " <>
             "a name that came out of a document must stay a binary, never an atom"
  end

  test "the names handed to the tag API are never interned" do
    warm_up()

    names = for i <- 1..@names, do: "probe-#{i}-not-a-tag"

    before = atom_count()
    tags = Enum.map(names, &Gumbo.Tag.from_name/1)
    originals = Enum.map(names, &Gumbo.Tag.from_original_text("<#{&1}>"))

    assert Enum.all?(tags, &(&1 == :unknown))
    assert Enum.all?(originals, &match?({:ok, _}, &1))

    assert atom_count() - before < @tolerance,
           "#{@names} distinct names through the tag API grew the atom table by " <>
             "#{atom_count() - before}, so an unknown name is being interned"
  end

  test "error records are never interned" do
    warm_up()

    html = Enum.map_join(1..@names, fn i -> "<div><em a#{i}=\"v\"</b></p><!!x#{i}><?#{i}?>" end)

    before = atom_count()
    {:ok, output} = Gumbo.parse(html, max_errors: -1)
    errors = Gumbo.materialize(output, detail: :full)[:errors]
    assert length(errors) >= @names

    assert atom_count() - before < @tolerance,
           "#{length(errors)} error records grew the atom table by #{atom_count() - before}"
  end

  # The NIF's own atoms — one per tag in gumbo's enum, plus the field keys of the two shapes — are
  # created once, when the library loads. Warming every path first keeps that one-time cost out of
  # the measurement, and a first call is also where a lazily-built atom would appear.
  defp warm_up do
    {:ok, output} = Gumbo.parse(~s(<x-warm data-warm="1">y</x-warm>))
    Gumbo.materialize(output, detail: :content)
    Gumbo.materialize(output, detail: :full)
    Node.descendants(Gumbo.Output.root(output)) |> Enum.each(&Node.tag_name/1)
    Gumbo.Tag.from_name("warm-up")
    Gumbo.Tag.from_original_text("<warm-up>")
    :ok
  end

  defp atom_count, do: :erlang.system_info(:atom_count)
end
