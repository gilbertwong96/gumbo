defmodule Gumbo.MixProject do
  use Mix.Project

  def project do
    [
      app: :gumbo,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_clean: ["clean"],
      aliases: aliases(),
      deps: deps(),
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "test.small_stack": fn _ ->
        System.cmd(
          "elixir",
          ["--erl", "+sssdcpu 20", "-S", "mix", "test", "--only", "small_stack"],
          into: IO.stream(),
          stderr_to_stdout: true
        )
      end
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:elixir_make, "~> 0.8", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # c_src is load-bearing: mix hex.build walks the filesystem, so listing it
  # publishes the submodule's checked-out contents as ordinary files and Hex
  # consumers need no git.
  defp package do
    [
      name: "gumbo",
      licenses: ["Apache-2.0"],
      files: ~w(lib c_src mix.exs Makefile README.md CHANGELOG.md LICENSE NOTICE)
    ]
  end

  defp docs do
    [main: "Gumbo"]
  end
end
