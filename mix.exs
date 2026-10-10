defmodule Gumbo.MixProject do
  use Mix.Project

  def project do
    [
      app: :gumbo,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_clean: ["clean"],
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
