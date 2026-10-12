defmodule Gumbo.ParseTest do
  use ExUnit.Case, async: true

  test "invalid UTF-8 is substituted and reported, not rejected" do
    html = "<p>" <> <<0xFF, 0xFE>> <> "</p>"
    assert {:ok, output} = Gumbo.parse(html)
    assert Gumbo.Output.node_count(output) > 0
  end

  test "check_size/1 rejects above the stack budget's limit" do
    assert Gumbo.Options.check_size(16_777_216) == :ok
    assert Gumbo.Options.check_size(16_777_217) == {:error, :input_too_large}
  end

  test "an input over the limit is refused end to end, by the NIF too" do
    over = String.duplicate("x", 16_777_217)

    assert {:error, :input_too_large} = Gumbo.parse(over)

    # Gumbo.Native.parse/2 is private but public in the NIF, so it is the
    # backstop: the same limit has to hold with the Elixir check bypassed.
    {:ok, opts} = Gumbo.Options.new([])

    assert {:error, :input_too_large} =
             Gumbo.Native.parse(over, Gumbo.Options.to_nif(opts))
  end

  test "an unknown or out-of-range option is rejected before parsing" do
    assert {:error, {:invalid_option, :nope, 1}} = Gumbo.parse("<p>", nope: 1)
    assert {:error, {:invalid_option, :tab_stop, 0}} = Gumbo.parse("<p>", tab_stop: 0)
  end

  test "values beyond C int range are rejected with the documented shape" do
    assert {:error, {:invalid_option, :max_errors, 3_000_000_000}} =
             Gumbo.parse("<p>", max_errors: 3_000_000_000)

    assert {:error, {:invalid_option, :tab_stop, 3_000_000_000}} =
             Gumbo.parse("<p>", tab_stop: 3_000_000_000)
  end

  test "the empty binary parses to an implied document" do
    assert {:ok, output} = Gumbo.parse("")
    assert Gumbo.Output.node_count(output) > 0
  end

  test "new/1 returns the defaults" do
    assert Gumbo.Options.new() == %Gumbo.Options{}
    assert Gumbo.Options.new([]) == {:ok, %Gumbo.Options{}}
  end

  test "new/1 validates every field against gumbo's documented ranges" do
    assert {:error, {:invalid_option, :tab_stop, 0}} = Gumbo.Options.new(tab_stop: 0)

    assert {:error, {:invalid_option, :stop_on_first_error, "yes"}} =
             Gumbo.Options.new(stop_on_first_error: "yes")

    assert {:error, {:invalid_option, :max_errors, -2}} = Gumbo.Options.new(max_errors: -2)

    assert {:error, {:invalid_option, :fragment_context, :not_a_tag}} =
             Gumbo.Options.new(fragment_context: :not_a_tag)

    assert {:error, {:invalid_option, :fragment_namespace, :xhtml}} =
             Gumbo.Options.new(fragment_namespace: :xhtml)

    assert {:error, {:invalid_option, :dirty, :sometimes}} = Gumbo.Options.new(dirty: :sometimes)
  end

  test "new/1 accepts a map and valid fragment options" do
    assert {:ok, %Gumbo.Options{tab_stop: 2}} = Gumbo.Options.new(%{tab_stop: 2})

    assert {:ok, %Gumbo.Options{fragment_context: :div, fragment_namespace: :svg}} =
             Gumbo.Options.new(fragment_context: :div, fragment_namespace: :svg)
  end

  test "dispatch/2 is the single scheduler policy, threshold included" do
    assert Gumbo.Options.dispatch(%Gumbo.Options{}, 20_479) == :normal
    assert Gumbo.Options.dispatch(%Gumbo.Options{}, 20_480) == :dirty
    assert Gumbo.Options.dispatch(%Gumbo.Options{dirty: true}, 1) == :dirty
    assert Gumbo.Options.dispatch(%Gumbo.Options{dirty: false}, 1_000_000) == :normal
    assert Gumbo.Options.dirty_threshold() == 20_480
  end

  test "parse!/2 raises ArgumentError with the reason" do
    assert_raise ArgumentError, ~r/nope/, fn -> Gumbo.parse!("<p>", nope: 1) end
  end

  # Two regression tests for a pair of quadratics in gumbo's tree construction,
  # both fixed by patches in c_src/patches/.
  #
  # Neither can be caught by check-parity, because parity compares the patched
  # build against the pinned sources: with a patch removed the two agree again,
  # and it passes. So the shapes have to be timed and measured here instead.
  test "deeply nested block tags parse in time linear in the depth" do
    # Before the 0002 patches this document took ~274 ms and its cost grew with the
    # square of the depth: the button-scope query walked the whole stack once per
    # block-level start tag. Now it is ~3 ms. The threshold splits those two by a
    # factor of 30 and 2.7 respectively, which is what makes it a regression test
    # rather than a machine-speed test.
    html = "<!doctype html>" <> String.duplicate("<div>", 20_000)

    {us, _} = :timer.tc(fn -> Gumbo.parse!(html) end)
    assert us < 100_000, "20 000 nested <div> took #{us} us"
  end

  test "an error deep in a document keeps at most 32 open-element tags" do
    # Errors arrive one per unclosed element or unmatched end tag, and each used to
    # keep the whole open-element stack: at this depth a 100 KB document cost 3.2 GB,
    # and a matching run of </p> cost 6.4 GB. The 0003 patch keeps the innermost 32,
    # so what is left is bounded by max_errors times 32 rather than by depth times
    # depth.
    deep = "<!doctype html>" <> String.duplicate("<div>", 20_000)
    burst = deep <> String.duplicate("</p>", 20_000)

    {:ok, capped} = Gumbo.parse(burst)
    errors = Gumbo.Output.errors(capped)
    assert length(errors) == Gumbo.Options.new([]) |> elem(1) |> Map.fetch!(:max_errors)

    stacks =
      Enum.map(errors, fn error ->
        assert %{tag_stack: stack} = Gumbo.Error.parser_error(error)
        length(stack)
      end)

    assert Enum.all?(stacks, &(&1 <= 32))
    # And the shape is still the document it was: the divs are what is deep.
    assert Gumbo.Node.tag(Gumbo.Output.root(capped)) == :html
  end

  test "an element over max_attributes is refused, not silently truncated" do
    over = "<!doctype html><div " <> Enum.map_join(1..1_100, " ", &"a#{&1}=1") <> ">"

    assert {:error, :too_many_attributes} = Gumbo.parse(over)

    # Inside the cap the same shape is fine, and -1 lifts the cap entirely.
    inside = "<div " <> Enum.map_join(1..1_000, " ", &"a#{&1}=1") <> ">"
    assert {:ok, _} = Gumbo.parse(inside, max_attributes: 1_000)
    assert {:ok, _} = Gumbo.parse(over, max_attributes: -1)
  end

  # The third quadratic: the duplicate-attribute check used to scan every attribute
  # already collected, so one element's attributes cost the square of their count.
  # 80 000 distinct names from 0.7 MB of input took 13.6 s before the 0004 patch and
  # 21 ms after, and the threshold below splits those by a factor of 100 and 40. The
  # cap is lifted on purpose: this is about the index, not about the ceiling.
  test "attribute counts parse in time linear in the count" do
    html = "<!doctype html><div " <> Enum.map_join(1..200_000, " ", &"a#{&1}=1") <> ">"

    {us, result} = :timer.tc(fn -> Gumbo.parse(html, max_attributes: -1) end)
    assert {:ok, _} = result
    assert us < 2_000_000, "200 000 attributes took #{us} us"
  end
end
