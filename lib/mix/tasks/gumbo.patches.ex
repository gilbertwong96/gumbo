defmodule Mix.Tasks.Gumbo.Patches do
  @shortdoc "Regenerates the vendored-parser patch series, or checks it"

  @moduledoc """
  Regenerates the vendored-parser patches from their definitions.

      mix gumbo.patches            # rewrite the patches whose definitions changed
      mix gumbo.patches --check    # assert the committed patches are what the definitions produce

  Every `.patch` under `c_src/patches/gumbo-parser/` that has a `.exs` of the same name
  is generated: the pinned source, the earlier patches applied with `git apply`, the
  definition's substitutions in order — each asserting how many occurrences it must
  find — and the diff of the pin against the result, preceded by the definition's
  header. `Gumbo.Patches` holds the machinery, including why the diff is a port of
  Python's `difflib` rather than any equivalent one.

  `--check` is what `make check-generators` runs: it writes nothing and fails when a
  regenerated patch differs by even one byte from the committed file. That is the net
  the Python tooling never had, and it is what makes "the tool still produces what the
  repository contains" a property someone can check instead of a belief.
  """

  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, strict: [check: :boolean])
    root = File.cwd!()
    defined = Gumbo.Patches.definitions(root) |> Enum.map(&elem(&1, 0))
    all = Gumbo.Patches.patches(root)

    if defined == [] do
      Mix.raise("no patch definitions found under c_src/patches/gumbo-parser")
    end

    if opts[:check], do: check(defined, all, root), else: regenerate(defined, all, root)
  end

  defp check(defined, all, root) do
    failures =
      for name <- defined, result = Gumbo.Patches.check(name, root), result != :ok do
        {name, result}
      end

    if failures == [] do
      report_match(defined, all)
    else
      Enum.each(failures, &report_mismatch(&1, root))
      Mix.raise("#{length(failures)} patch(es) do not match their definitions")
    end
  end

  defp report_match(defined, all) do
    count = length(defined)
    skipped = length(all) - count

    extra =
      if skipped > 0,
        do: " (#{skipped} hand-written patch(es) are not generated and not checked)",
        else: ""

    Mix.shell().info("PASS: #{count} patch(es) regenerate byte-identically#{extra}")
  end

  defp report_mismatch({name, result}, root) do
    case result do
      {:changed, generated} ->
        Mix.shell().error("#{name}.patch differs from what its definition produces")

        report_difference(
          generated,
          File.read!(Path.join([root, "c_src/patches/gumbo-parser", name <> ".patch"]))
        )

      {:missing, _generated} ->
        Mix.shell().error("#{name}.patch is missing")
    end
  end

  defp report_difference(generated, committed) do
    generated = String.split(generated, "\n")
    committed = String.split(committed, "\n")

    Enum.zip(generated, committed)
    |> Enum.with_index(1)
    |> Enum.reject(fn {{a, b}, _} -> a == b end)
    |> Enum.take(3)
    |> Enum.each(fn {{a, b}, line} ->
      Mix.shell().error("  line #{line}:")
      Mix.shell().error("    regenerated: #{inspect(a)}")
      Mix.shell().error("    committed:   #{inspect(b)}")
    end)

    if length(generated) != length(committed) do
      Mix.shell().error(
        "  lengths: regenerated #{length(generated)}, committed #{length(committed)}"
      )
    end
  end

  defp regenerate(defined, all, root) do
    results = for name <- defined, do: {name, Gumbo.Patches.write(name, root)}

    written = for {name, :written} <- results, do: name

    if written == [] do
      Mix.shell().info("#{length(defined)} patch(es) already match their definitions")
    else
      for name <- written, do: Mix.shell().info("rewrote #{name}.patch")
    end

    skipped = length(all) - length(defined)

    if skipped > 0 do
      Mix.shell().info("#{skipped} hand-written patch(es) left alone")
    end
  end
end
