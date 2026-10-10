defmodule Gumbo.ParseTest do
  use ExUnit.Case, async: true

  test "invalid UTF-8 is substituted and reported, not rejected" do
    html = "<p>" <> <<0xFF, 0xFE>> <> "</p>"
    assert {:ok, output} = Gumbo.parse(html)
    assert Gumbo.Output.node_count(output) > 0
  end

  test "check_size/1 rejects above 4 GB" do
    assert Gumbo.Options.check_size(4_294_967_295) == :ok
    assert Gumbo.Options.check_size(4_294_967_296) == {:error, :input_too_large}
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
end
