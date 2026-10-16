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

  test "large parses do not starve a normal scheduler" do
    html = HTML.nested("div", 2_000) <> String.duplicate("<p>text</p>", 5_000)

    # This is a contrast measured inside one run, not an absolute bound: the same
    # document is parsed twice, once forced onto a normal scheduler and once left to
    # the dispatch, and what is compared is how long a normal scheduler waited for its
    # turn under each. An absolute bound could only ever be about the runner — the
    # first release rehearsal measured 11.9 ms on an Intel macOS runner, past the
    # 10 ms bound the earlier form used, while a missing dirty dispatch produced the
    # same 28-50 ms there that it produces here. The ratio is what the dispatch
    # decides, and it does not move with the runner: well over 100 where this was
    # written, and 1489 us against 11981 us — a factor of 8 — on an aarch64 macOS
    # runner. A dispatch that sends the large parse to a normal scheduler collapses it:
    # forcing the dispatch off measured 14478 us against 33031 us (2.3) on the machine
    # this was written on, and 28585 us against 31360 us (1.1) before that. Four is
    # between the two bands, not ten: ten was the bound that made a shared runner fail.
    #
    # What still fails this test: a dispatch that sends the large parse to a normal
    # scheduler, however it is broken — the ratio then collapses to about 1.
    #
    # The ticker spawns the parsers itself, so its scheduler's run queue holds parser
    # tasks when it yields and the loop cannot finish before the storm starts.
    # 2 x schedulers_online, each parsing twice, keeps every normal scheduler busy for
    # ~2 parse durations when the dirty dispatch is missing. Three storms per side, and
    # each side's smallest max-gap is its result.
    storm = fn options ->
      ticker =
        Task.async(fn ->
          parsers =
            for _ <- 1..(System.schedulers_online() * 2) do
              Task.async(fn -> for _ <- 1..2, do: Gumbo.parse(html, options) end)
            end

          gaps =
            Enum.map(1..2000, fn _ ->
              t0 = System.monotonic_time(:microsecond)
              :erlang.yield()
              System.monotonic_time(:microsecond) - t0
            end)

          Enum.each(parsers, &Task.await/1)
          Enum.max(gaps)
        end)

      Task.await(ticker)
    end

    forced_normal = Enum.min(Enum.map(1..3, fn _ -> storm.(dirty: false) end))
    dispatched = Enum.min(Enum.map(1..3, fn _ -> storm.([]) end))

    assert dispatched * 4 < forced_normal,
           "a normal scheduler waited #{dispatched} us while the large parse was dispatched " <>
             "by size, and #{forced_normal} us when it was forced onto a normal one"
  end

  # Deliberately no test for the no-dirty-schedulers fallback in run/4: the
  # fallback branch is unreachable on a dirty-scheduler VM and any assertion
  # comparing dirty_schedulers?/0 against the expression it must equal is
  # self-referential, so such a test could never fail. The guard's existence
  # is pinned incidentally — run/4 calls it on every dirty-path parse, so
  # removing it fails "both paths produce the same tree" above. See the
  # comment at Gumbo.Native.dirty_schedulers?/0 for why it is not a NIF.
end
