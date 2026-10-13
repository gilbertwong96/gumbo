defmodule Mix.Tasks.Gumbo.PatchesTest do
  # async: false — these tests change the working directory.
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Gumbo.Patches
  alias Gumbo.Test.Fixtures, as: Fixtures

  test "--check passes in the repository and reports what it checked" do
    output = capture_io(fn -> Mix.Task.rerun("gumbo.patches", ["--check"]) end)
    assert output =~ "PASS: 5 patch(es) regenerate byte-identically"
    assert output =~ "hand-written patch(es) are not generated and not checked"
  end

  test "no --check rewrites a stale patch and says which" do
    root = Fixtures.fake_root(%{patch: "stale\n"})
    in_dir(root, fn -> Mix.Task.rerun("gumbo.patches", []) end)

    assert File.read!(Path.join(root, "c_src/patches/gumbo-parser/0001-fixture.patch")) ==
             Patches.generate("0001-fixture", root)
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
