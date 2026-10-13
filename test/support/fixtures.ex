defmodule Gumbo.Test.Fixtures do
  @moduledoc """
  Builds fake repo roots for exercising `Gumbo.Patches` away from the tracked
  sources. Each root is self-sufficient — one patch definition, the pinned
  file it substitutes into, and optionally the committed patch — so a test can
  assert on shapes the real definitions cannot take.
  """

  @source "fixture.txt"
  @name "0001-fixture"

  @doc """
  Builds a fake root under the repo's gitignored `tmp/` and returns its
  absolute path. Every call gets its own directory, so `async: true` tests
  never collide.

  ## Options

    * `:patch` — the committed patch's bytes: `:generated` writes what
      `Gumbo.Patches.generate/2` produces, `nil` writes nothing, a binary is
      written as-is. Defaults to `nil`.
    * `:count` — the definition's expected occurrences, default `1`.
    * `:file_body` — the pinned file's content, default `"alpha\n"`, which
      makes the default substitution match exactly once.
    * `:definition` — `false` writes no `.exs` definition. Defaults to `true`.
    * `:priors` — the definition's `priors` flag: `true` makes generation apply
      the earlier-numbered patches first. Defaults to `false`.
    * `:extra_patches` — extra `{name, bytes}` written as `.patch` files next to
      the fixture's own. Defaults to `[]`.
  """
  @spec fake_root(map()) :: binary()
  def fake_root(opts \\ %{}) do
    root = Path.expand("../../tmp/generator-#{next()}", __DIR__)

    # The sequence restarts with every VM, so a previous run's directory with
    # the same number must not leak its files into this one.
    File.rm_rf!(root)
    File.mkdir_p!(Path.join(root, "c_src/gumbo-parser/src"))
    File.mkdir_p!(Path.join(root, "c_src/patches/gumbo-parser"))

    File.write!(
      Path.join([root, "c_src/gumbo-parser/src", @source]),
      Map.get(opts, :file_body, "alpha\n")
    )

    if Map.get(opts, :definition, true) do
      definition = %{
        priors: Map.get(opts, :priors, false),
        header: "Subject: [PATCH] fixture\n\n",
        subs: [%{file: @source, count: Map.get(opts, :count, 1), from: "alpha", to: "beta"}]
      }

      File.write!(
        Path.join([root, "c_src/patches/gumbo-parser", @name <> ".exs"]),
        inspect(definition, pretty: true, limit: :infinity)
      )
    end

    case Map.get(opts, :patch) do
      nil -> :ok
      :generated -> File.write!(patch_path(root), Gumbo.Patches.generate(@name, root))
      bytes -> File.write!(patch_path(root), bytes)
    end

    Enum.each(Map.get(opts, :extra_patches, []), fn {name, bytes} ->
      File.write!(Path.join([root, "c_src/patches/gumbo-parser", name <> ".patch"]), bytes)
    end)

    root
  end

  defp patch_path(root), do: Path.join([root, "c_src/patches/gumbo-parser", @name <> ".patch"])

  defp next, do: System.unique_integer([:positive, :monotonic])
end
