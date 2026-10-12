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
      dialyzer: dialyzer(),
      package: package(),
      docs: docs()
    ]
  end

  # `mix test` refuses to run inside another command's dev-env VM, and
  # running the chain in :test keeps every step on one environment: compile
  # then also covers test/support, and dialyzer gets its own PLT under
  # _build/test/plts instead of sharing dev's.
  def cli do
    [preferred_envs: [ci: :test]]
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
      ci: [
        "compile --all-warnings --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "deps.unlock --check-unused",
        "xref graph --label compile-connected --fail-above 0",
        "dialyzer",
        "ex_dna",
        "reach.check --dead-code --smells --strict",
        "ci.dead_code",
        "test",
        "test.small_stack",
        "test.teardown_contract",
        "check.patch",
        "check.parity",
        "check.stack_guard",
        "check.analyzer",
        "check.c_format",
        "check.c_lint",
        "check.sanitizers",
        "check.clean_build"
      ],

      # `reach.check --dead-code` only renders: unlike --smells it never reads
      # --strict, so on its own it cannot fail the build. These are the two
      # entry points the task itself uses, with a non-empty finding list
      # turned into a failure. Coupled to reach's internals, pinned at ~> 2.8.
      "ci.dead_code": fn _ ->
        Mix.Task.run("compile")
        findings = Reach.Check.DeadCode.run(Reach.Check.DeadCode.collect_files(nil), [])

        if findings != [] do
          Mix.raise(
            "reach.check --dead-code found #{length(findings)} finding(s); " <>
              "run `mix reach.check --dead-code` to see them"
          )
        end
      end,
      "test.small_stack": fn _ ->
        # The child VM's exit status must propagate: a destructor crash
        # (e.g. SIGBUS, reported by System.cmd as exit status 138) has to
        # fail the alias or the safety net silently never trips.
        {_output, status} =
          System.cmd(
            "elixir",
            ["--erl", "+sssdcpu 20", "-S", "mix", "test", "--only", "small_stack"],
            into: IO.stream(),
            stderr_to_stdout: true
          )

        if status != 0 do
          Mix.raise("test.small_stack failed with status #{inspect(status)}")
        end
      end,
      # The vendored sources are patched out of tree, so the patch has to keep
      # applying: a submodule bump that rots it must be a red build, not a build
      # that compiles unpatched gumbo and quietly loses the fix. make's exit
      # status carries that, so it has to propagate.
      "check.patch": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-patch"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check.patch failed with status #{inspect(status)}")
        end
      end,
      # The build has to work from an empty object directory: that is what a fresh
      # clone, a cold CI cache and a hex consumer all do, and it is the one path the
      # warm tree this gate runs in cannot test. Both a stale object rule and the
      # -include handling of a not-yet-written .d file were wrong exactly there.
      # The patches change how the parser decides what to build, and an answer that
      # is off by one does not crash or leak — it silently produces a different
      # tree, which is the one thing the shape matrix cannot see. make check-parity
      # parses a seeded corpus with the patched objects and with the pinned sources
      # and compares the trees node by node. It found two silent-corruption bugs in
      # the second patch, so it stays.
      "check.parity": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-parity"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check.parity failed with status #{inspect(status)}")
        end
      end,
      # The only net for a memory-safety bug inside gumbo itself, which is residual 2 of
      # the list of what could still take the VM down. AddressSanitizer and
      # UndefinedBehaviorSanitizer over the corpus and the adversarial shapes. It found
      # the fourth patch's missing initialisation: without ASan the tokenizer state
      # happened to come from zeroed pages, and ASan's byte pattern turned a latent
      # garbage pointer into an assertion failure. Slow — the instrumented build of the
      # twelve vendored files is most of it — and worth it.
      # The stack guard is the backstop for the recursion nobody has found, and the
      # property that makes it worth having is that it cannot be reached from here: the
      # sized-stack decision hands the parse a stack the budget says is enough, so only an
      # arithmetic mistake or an unmeasured recursion can trip it. It is exercised at the
      # C level with a budget smaller than one frame's worth of parsing, which is what
      # make check-stack-guard does.
      "check.stack_guard": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-stack-guard"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check.stack_guard failed with status #{inspect(status)}")
        end
      end,
      # The only net for our own C, which is the newest and least exercised code in the
      # repository, and the only one that can look at anything at all where the sanitizers
      # cannot reach (instrumenting our NIF would mean instrumenting the VM). It is clean
      # today, and two attempts to verify it were needed to establish that "clean" was
      # worth anything: the first injected bug was unreachable dead code, which the analyzer
      # prunes, and the second used enif_alloc/enif_free, which it cannot model because they
      # are declarations in a header. A null dereference in an exported function is what
      # proved the gate can fail.
      "check.analyzer": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-analyzer"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check.analyzer failed with status #{inspect(status)}")
        end
      end,
      # The C half of what mix format and the compiler already do for Elixir. clang-format
      # against .clang-format, which is Google's style because that is what gumbo is written
      # in, so a patch and the file it patches read the same way; and warnings as errors on
      # our own C with the classes -Wall -Wextra leaves out.
      #
      # Both are clean today, and the lint one is how the two findings that started it were
      # found: a function that should have been static, and an int where a GumboParseFlags
      # bit was meant.
      "check.c_format": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-c-format"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check.c_format failed with status #{inspect(status)}")
        end
      end,
      "check.c_lint": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-c-lint"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check.c_lint failed with status #{inspect(status)}")
        end
      end,
      "check.sanitizers": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-sanitizers"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check.sanitizers failed with status #{inspect(status)}")
        end
      end,
      "check.clean_build": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-clean-build"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check.clean_build failed with status #{inspect(status)}")
        end
      end,
      "test.teardown_contract": fn _ ->
        # make's exit status must propagate: check-teardown fails the build on a
        # non-zero allocator balance, and on a canary signal death — which after
        # c_src/patches/0001 can only mean the patch was lost. Both are the point
        # of running it, so the alias must fail too.
        {_output, status} =
          System.cmd("make", ["check-teardown"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check-teardown failed with status #{inspect(status)}")
        end
      end
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  # PLTs live inside _build so a cold checkout never inherits a global
  # ~/.mix PLT: those are keyed by Erlang/Elixir version alone, so a PLT
  # built by a different install of the same version is silently reused
  # and then fails with paths that no longer exist.
  defp dialyzer do
    [
      plt_local_path: "_build/plts",
      plt_core_path: "_build/plts"
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.8", runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:reach, "~> 2.8", only: [:dev, :test], runtime: false}
    ]
  end

  # c_src is load-bearing: mix hex.build walks the filesystem, so listing it
  # publishes the submodule's checked-out contents as ordinary files and Hex
  # consumers need no git.
  defp package do
    [
      description:
        "A faithful Elixir binding to gumbo-parser 0.14.1: spec-conformant " <>
          "HTML5 parsing into a lazy native handle or plain Elixir data.",
      name: "gumbo",
      licenses: ["Apache-2.0"],
      links: %{
        "gumbo-parser" => "https://codeberg.org/gumbo-parser/gumbo-parser",
        # PLACEHOLDER: guessed, no git remote exists yet — see docs/0.
        "Source" => "https://github.com/elixir-gumbo/gumbo"
      },
      files: ~w(lib c_src mix.exs Makefile README.md CHANGELOG.md LICENSE NOTICE)
    ]
  end

  # PLACEHOLDER: the repo has no git remote yet, so the URLs below are
  # guesses. The owner must substitute the real repository URL before a
  # public Hex release.
  defp docs do
    [
      main: "Gumbo",
      source_url: "https://github.com/elixir-gumbo/gumbo",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
