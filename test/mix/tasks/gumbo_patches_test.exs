defmodule Mix.Tasks.Gumbo.PatchesTest do
  # async: false — these tests change the working directory.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Gumbo.Patches
  alias Gumbo.Test.Fixtures, as: Fixtures

  test "--check passes in the repository and reports what it checked" do
    output = capture_io(fn -> Mix.Task.rerun("gumbo.patches", ["--check"]) end)
    assert output =~ "PASS: 9 patch(es) regenerate byte-identically"
    assert output =~ "hand-written patch(es) are not generated and not checked"
  end

  test "no --check writes a patch that has no committed file yet" do
    # What the definition used to have no way through: a new patch needed a
    # placeholder, and a placeholder is a `.patch` the build tried to apply.
    root = Fixtures.fake_root(%{patch: nil})

    output =
      capture_io(fn ->
        in_dir(root, fn -> Mix.Task.rerun("gumbo.patches", []) end)
      end)

    assert output == "wrote 0001-fixture.patch\n"

    assert File.read!(Path.join(root, "c_src/patches/gumbo-parser/0001-fixture.patch")) ==
             Patches.generate("0001-fixture", root)
  end

  test "no --check rewrites a stale patch and says which" do
    root = Fixtures.fake_root(%{patch: "stale\n"})

    output =
      capture_io(fn ->
        in_dir(root, fn -> Mix.Task.rerun("gumbo.patches", []) end)
      end)

    assert output == "rewrote 0001-fixture.patch\n"

    assert File.read!(Path.join(root, "c_src/patches/gumbo-parser/0001-fixture.patch")) ==
             Patches.generate("0001-fixture", root)
  end

  test "no --check with a patch that already matches reports it instead of rewriting" do
    root = Fixtures.fake_root(%{patch: :generated})

    output =
      capture_io(fn ->
        in_dir(root, fn -> Mix.Task.rerun("gumbo.patches", []) end)
      end)

    assert output == "1 patch(es) already match their definitions\n"
  end

  test "no --check reports hand-written patches as left alone" do
    root =
      Fixtures.fake_root(%{patch: :generated, extra_patches: [{"0000-hand", "hand-written\n"}]})

    output =
      capture_io(fn ->
        in_dir(root, fn -> Mix.Task.rerun("gumbo.patches", []) end)
      end)

    assert output ==
             "1 patch(es) already match their definitions\n" <>
               "1 hand-written patch(es) left alone\n"
  end

  test "--check with every patch defined reports no hand-written parenthetical" do
    root = Fixtures.fake_root(%{patch: :generated})

    output =
      capture_io(fn ->
        in_dir(root, fn -> Mix.Task.rerun("gumbo.patches", ["--check"]) end)
      end)

    assert output == "PASS: 1 patch(es) regenerate byte-identically\n"
  end

  test "--check fails loudly when a patch differs, naming the first differing lines" do
    root = Fixtures.fake_root(%{patch: "stale\n"})

    output =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn ->
          in_dir(root, fn -> Mix.Task.rerun("gumbo.patches", ["--check"]) end)
        end
      end)

    assert output =~ "0001-fixture.patch differs"
    assert output =~ "regenerated:"
    assert output =~ "committed:"
    assert output =~ "lengths: regenerated"
  end

  test "--check fails when a definition produces no committed file at all" do
    root = Fixtures.fake_root(%{patch: nil})

    output =
      capture_io(:stderr, fn ->
        assert_raise Mix.Error, fn ->
          in_dir(root, fn -> Mix.Task.rerun("gumbo.patches", ["--check"]) end)
        end
      end)

    assert output =~ "0001-fixture.patch is missing"
  end

  test "a tree with no definitions refuses to pretend it checked anything" do
    root = Fixtures.fake_root(%{definition: nil})

    message =
      assert_raise Mix.Error, fn ->
        in_dir(root, fn -> Mix.Task.rerun("gumbo.patches", ["--check"]) end)
      end

    assert message.message =~ "no patch definitions found"
  end

  defp in_dir(dir, fun) do
    original = File.cwd!()
    File.cd!(dir)

    try do
      fun.()
    after
      File.cd!(original)
    end
  end
end
