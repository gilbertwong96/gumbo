defmodule Gumbo.SchedulerTest do
  use ExUnit.Case, async: false

  alias Gumbo.Test.HTML

  test "dispatch follows size and the explicit override" do
    options = Gumbo.Options.new()
    assert Gumbo.Options.dispatch(options, 20_479) == :normal
    assert Gumbo.Options.dispatch(options, 20_480) == :dirty

    # new/1 with arguments returns {:ok, options} — the brief's verbatim
    # Gumbo.Options.new(dirty: true) call yields a tuple, not the struct.
    assert {:ok, forced} = Gumbo.Options.new(dirty: true)
    assert Gumbo.Options.dispatch(forced, 1) == :dirty
    assert {:ok, forbidden} = Gumbo.Options.new(dirty: false)
    assert Gumbo.Options.dispatch(forbidden, 1_000_000) == :normal
  end

  test "both paths produce the same tree" do
    html = HTML.nested("span", 5_000)
    {:ok, auto} = Gumbo.parse(html)
    {:ok, forced_normal} = Gumbo.parse(html, dirty: false)
    {:ok, forced_dirty} = Gumbo.parse(html, dirty: true)
    assert Gumbo.Output.node_count(auto) == Gumbo.Output.node_count(forced_normal)
    assert Gumbo.Output.node_count(auto) == Gumbo.Output.node_count(forced_dirty)
  end

  test "both materialize paths produce the same term" do
    # 11 000 <p>text</p> elements is 22 003 nodes, past the 20 480-node
    # materialize threshold, so :auto and dirty: true take the dirty NIFs.
    {:ok, output} = Gumbo.parse(String.duplicate("<p>text</p>", 11_000))
    assert Gumbo.Output.node_count(output) >= 20_480

    assert Gumbo.materialize(output) == Gumbo.materialize(output, dirty: false)
    assert Gumbo.materialize(output) == Gumbo.materialize(output, dirty: true)

    root = Gumbo.Output.root(output)
    assert Gumbo.materialize(root) == Gumbo.materialize(root, dirty: false)
    assert Gumbo.materialize(root) == Gumbo.materialize(root, dirty: true)
  end

  test "materialize validates the dirty option like parse does" do
    {:ok, output} = Gumbo.parse("<p>x</p>")

    assert_raise ArgumentError, ~r/invalid dirty/, fn ->
      Gumbo.materialize(output, dirty: :sometimes)
    end
  end

  # Deliberately no test that a large parse does not starve a normal scheduler, though
  # there were four of them. Each measured how long a process on a normal scheduler waited
  # for its turn while schedulers_online() * 4 parsers of a 77 KB document ran four times
  # each, and each turned out to compare the machine rather than the dispatch:
  #
  #   * an absolute bound (10 ms), which the first release rehearsal broke with 11.9 ms on
  #     an Intel macOS runner, while a missing dirty dispatch produced 28-50 ms there;
  #   * the ratio of a forced-normal storm to a dispatched one, which an aarch64 macOS
  #     runner measured at 2.2 and 8 — overlapping the 1.1-2.3 that forcing the dispatch off
  #     produces, so no threshold separates the two states;
  #   * the same ratio with a ticker per scheduler, which is better and still failed one run
  #     in five, and in CI twice;
  #   * the same bounded by time instead of by yields, which is what showed why: 2000 yields
  #     can finish in 0.2 ms when the parsers the ticker just spawned have not been scheduled
  #     yet, so the probe misses the storm and reports a gap that says nothing. Bounded by
  #     time it cannot miss it, and then the dispatched side measured 16-48 ms against 59-82 ms
  #     forced — a factor of 1.2 to 3.4, against the 0.1-0.2 ms the yield-bounded shapes
  #     reported. The apparent separation had been the measurement not happening.
  #
  # What is pinned instead: dispatch/2 by size and by override (the first test above), both
  # paths producing the same tree, and both materialize paths producing the same term. Those
  # pin the choice and the equivalence of the two paths — not that a parse the dispatch sent
  # to a dirty scheduler really runs on one, which is the property this file has no gate for,
  # because neither this machine nor a shared runner can tell the two states apart.

  # Deliberately no test for the no-dirty-schedulers fallback in run/4: the
  # fallback branch is unreachable on a dirty-scheduler VM and any assertion
  # comparing dirty_schedulers?/0 against the expression it must equal is
  # self-referential, so such a test could never fail. The guard's existence
  # is pinned incidentally — run/4 calls it on every dirty-path parse, so
  # removing it fails "both paths produce the same tree" above. See the
  # comment at Gumbo.Native.dirty_schedulers?/0 for why it is not a NIF.
end
