defmodule Gumbo.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :gumbo,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:elixir_make] ++ Mix.compilers(),
      make_clean: ["clean"],
      # Precompiled NIFs. cc_precompiler gives elixir_make a target triple for the host it is
      # building on, and elixir_make downloads the matching archive from the release below instead
      # of running the C build; when no archive matches, `make_precompiler_unavailable_target`
      # falls back to compiling from the sources in this package, which is why `files:` below still
      # carries the patches and the pinned vendored parser.
      #
      # The filename is named explicitly because the shared library is `gumbo_nif` while the app is
      # `gumbo`; priv_paths is narrowed to the library alone because `priv/obj` is C build scratch
      # that has no business in a released archive.
      make_precompiler: {:nif, CCPrecompiler},
      make_precompiler_filename: "gumbo_nif",
      make_precompiler_priv_paths: ["gumbo_nif.*"],
      make_precompiler_url:
        "https://github.com/gilbertwong96/gumbo/releases/download/v#{@version}/@{artefact_filename}",
      # Local work always compiles: an archive for the version being worked on cannot exist yet, and
      # a release run is the only place where fetching instead of building is the point. The key is
      # `make_force_build`, not `force_build` — elixir_make reads the former, and the latter is
      # silently ignored, which is how a build can end up doing neither: no download, no compile.
      make_force_build: Mix.env() != :prod,
      # The Windows target key is what a consumer's elixir_make matches against what their OTP
      # reports, and the official Windows Erlang builds are MSVC — so the key says msvc. The
      # toolchain here is mingw, because this project's C needs pthreads and MSVC has none; an
      # MSVC-built VM loads a mingw-built DLL, which the Windows job in ci.yml proves on every push.
      # Without this override cc_precompiler hands the driver `cl`, which does not exist in the MSYS2
      # environment that job builds in — that is how the first release rehearsal failed.
      cc_precompiler: [
        compilers: %{
          # Merge into cc_precompiler's own tables rather than replacing them. The darwin entries
          # carry the -arch flags its two targets need, so a map that only names Windows silently
          # leaves clang building for the host and produces an archive named for one architecture
          # containing the other. `true` means "my entries win, yours fill the rest".
          {:unix, :darwin} => %{include_default_ones: true},
          {:unix, :linux} => %{include_default_ones: true},
          {:win32, :nt} => %{include_default_ones: true, "x86_64-windows-msvc" => {"gcc", "g++"}}
        }
      ],
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      # ExCoveralls, because the number is published: codecov reads the coveralls JSON that
      # `mix coveralls.json` writes. The floor moved with the tool — from the built-in :cover
      # summary to coveralls.json's `minimum_coverage` — and stayed the same 92 for the same
      # reason: three classes of line cannot be covered and none of them is excluded from the
      # measurement. Gumbo.Patches.Diff's dead `split/5` clause, Gumbo.Native's load_nif/0 raise
      # (only a broken build runs it), and Gumbo.Native's thirty-odd pre-load stub bodies, which
      # :cover instruments, load_nif/2 replaces, and NIF entries are invisible to coverage, so no
      # test can cover them. `mix coveralls` enforces the floor; `mix coveralls.json` only writes
      # the file codecov reads, which is why the uploaded number is never the gate.
      test_coverage: [tool: ExCoveralls],
      package: package(),
      docs: docs()
    ]
  end

  # `mix test` refuses to run inside another command's dev-env VM, and
  # running the chain in :test keeps every step on one environment: compile
  # then also covers test/support, and dialyzer gets its own PLT under
  # _build/test/plts instead of sharing dev's.
  # `ci` runs the whole chain in :test, and the coveralls tasks are :test tasks too: naming them
  # here is what keeps `mix coveralls` from needing a MIX_ENV prefix that only CI would remember.
  def cli do
    [preferred_envs: [ci: :test, coveralls: :test, "coveralls.json": :test]]
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
        # The threshold in project/0 is a gate or it is a report: run the covered suite here so
        # the number cannot rot silently.
        "test.covered",
        "test.small_stack",
        "test.teardown_contract",
        "check.patch",
        "check.generators",
        "check.parity",
        "check.stack_guard",
        "check.analyzer",
        "check.c_format",
        "check.c_lint",
        "check.c_tidy",
        "check.failure_returns",
        "check.sanitizers",
        "check.clean_build",
        "test.fault_paths"
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
      # The allocation-failure paths, by making an extraction fail on purpose. make owns the fault
      # build and puts the shipping library back afterwards, so the alias is only the entry point.
      "test.fault_paths": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-fault-paths"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("test.fault_paths failed with status #{inspect(status)}")
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
      # Like test.small_stack, the covered suite gets its own VM. Cover forces a recompile and
      # reload, which re-runs Gumbo.Native's @on_load; in a VM that already has the NIF
      # registered that load_nif/2 call fails with {:upgrade, ...}, the module drops out of the
      # table, and the suite's lowest line is erased from the ci sum. A fresh VM loads the NIF
      # exactly once, so the table keeps all modules and the log stays clean.
      "test.covered": fn _ ->
        # `mix coveralls` is what enforces coveralls.json's minimum_coverage, so its exit status
        # must propagate or the gate is a report. The child VM is not about isolation: inside
        # `mix ci`'s single VM the dead-code steps have already loaded Gumbo.Native, cover's forced
        # reload of it then fails with {:upgrade, …}, and the lowest module silently drops out of
        # the table — the exact shape the no-ignore_modules rule exists to prevent.
        {_output, status} =
          System.cmd(
            "elixir",
            ["-S", "mix", "coveralls"],
            into: IO.stream(),
            stderr_to_stdout: true
          )

        if status != 0 do
          Mix.raise("test.covered failed with status #{inspect(status)}")
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
      # The patch definitions had no check of their own before this: a definition could stop
      # reproducing its patch and nothing would say so — and one already had, in the rebase
      # recipe. This regenerates every defined patch and requires the committed bytes.
      "check.generators": fn _ ->
        Mix.Task.rerun("gumbo.patches", ["--check"])
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
      # clang-tidy with the checks in .clang-tidy, over our C, with the vendored sources and
      # the ERTS headers as system headers so that findings are attributed to our code. The
      # first run reported 125 signed-bitwise findings and every one of them was inside
      # gumbo.h, which is what that distinction is for.
      "check.failure_returns": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-failure-returns"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check.failure_returns failed with status #{inspect(status)}")
        end
      end,
      "check.c_tidy": fn _ ->
        {_output, status} =
          System.cmd("make", ["check-c-tidy"], into: IO.stream(), stderr_to_stdout: true)

        if status != 0 do
          Mix.raise("check.c_tidy failed with status #{inspect(status)}")
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
      plt_core_path: "_build/plts",
      # The patch generator is a Mix.Task (`mix gumbo.patches`), so `:mix` has to be in
      # the PLT: without it its `Mix.raise/1` and `Mix.shell/0` calls are unknown
      # functions and the Mix.Task callback is an unknown behaviour. This is the whole
      # of that dependency — no other module here touches Mix.
      plt_add_apps: [:mix]
    ]
  end

  defp deps do
    [
      # cc_precompiler is what lets this library ship precompiled NIFs; the `make_precompiler*` keys
      # in project/0 are its other half. Its requirement is `elixir_make ~> 0.7 or ~> 0.8 or ~> 0.9`,
      # which — since two-segment requirements mean "below 1.0" — already admits the 0.10 this
      # project locks, so nothing here is pinned back for it.
      {:cc_precompiler, "~> 0.1", runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:elixir_make, "~> 0.8", runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      # What the README's coverage badge shows. The gate is coveralls.json's minimum_coverage,
      # enforced by `mix coveralls` in mix ci's test.covered step; this dependency exists only to
      # write the coveralls format codecov reads, so it stays out of the runtime and out of every
      # env but :test.
      {:excoveralls, "~> 0.18", only: [:test], runtime: false},
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
        "Source" => "https://github.com/gilbertwong96/gumbo"
      },
      # c_src/gumbo-parser is a git submodule, and a Hex package cannot carry a submodule — it
      # carries the files. So the package names the pinned parser's sources directly, and a release
      # from a checkout whose submodule is not initialised would ship a package that cannot compile:
      # the release workflow checks for exactly that.
      files: ~w(
        lib c_src/*.c c_src/*.h c_src/patches c_src/test c_src/gumbo-parser/src
        mix.exs Makefile coveralls.json checksum.exs README.md CHANGELOG.md LICENSE NOTICE
      )
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
