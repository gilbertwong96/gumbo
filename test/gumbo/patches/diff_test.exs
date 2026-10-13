defmodule Gumbo.Patches.DiffTest do
  use ExUnit.Case, async: true

  alias Gumbo.Patches.Diff

  # Every expectation here is what Python's difflib produced for the same input, not
  # what looked right: the point of the port is that a regenerated patch is
  # byte-identical to the Python generators' output, so an expectation reasoned out
  # here would be a different thing being tested.

  defp diff(a, b) do
    Diff.unified(Diff.splitlines(a), Diff.splitlines(b), "a/src/x", "b/src/x")
  end

  test "a replacement in the middle" do
    assert diff("a\nb\nc\nd\ne\nf\n", "a\nb\nZ\nd\ne\nf\n") ==
             ~S"""
             --- a/src/x
             +++ b/src/x
             @@ -1,6 +1,6 @@
              a
              b
             -c
             +Z
              d
              e
              f
             """
  end

  test "an insertion" do
    assert diff("a\nb\nc\nd\ne\nf\n", "a\nb\nc\nX\nd\ne\nf\n") ==
             ~S"""
             --- a/src/x
             +++ b/src/x
             @@ -1,6 +1,7 @@
              a
              b
              c
             +X
              d
              e
              f
             """
  end

  # Fourteen unchanged lines between two changes is more than twice the context, so
  # they are two hunks rather than one, and each carries three lines of context.
  test "changes far apart become separate hunks" do
    a = Enum.map_join(0..19, &"l#{&1}\n")
    b = Enum.map_join(0..19, fn i -> if i in [2, 17], do: "CHANGED\n", else: "l#{i}\n" end)

    assert diff(a, b) ==
             ~S"""
             --- a/src/x
             +++ b/src/x
             @@ -1,6 +1,6 @@
              l0
              l1
             -l2
             +CHANGED
              l3
              l4
              l5
             @@ -15,6 +15,6 @@
              l14
              l15
              l16
             -l17
             +CHANGED
              l18
              l19
             """
  end

  # difflib prefixes a final line that has no terminator and adds nothing, so the last
  # line of the patch has none either. Pinned because it is the kind of detail a port
  # gets wrong silently.
  test "a final line without a newline stays without one" do
    assert diff("a\nb", "a\nB") == "--- a/src/x\n+++ b/src/x\n@@ -1,2 +1,2 @@\n a\n-b+B"
  end

  test "no changes mean no output" do
    assert diff("a\nb\n", "a\nb\n") == ""
  end

  # Both sides empty is difflib's empty-opcodes case: unified_diff([], []) produces
  # no output at all, so the port must return "" rather than anything else.
  test "two empty files diff to nothing" do
    assert diff("", "") == ""
  end

  # A one-line hunk with context 0 is the only shape that renders a zero-length
  # range: difflib trims the leading equal to (9, 9, 9, 9), so take/3 gets an
  # empty range and emits nothing. Expectation is difflib's n=0 output.
  test "a one-line hunk with zero context" do
    a = Enum.map(0..9, &"l#{&1}\n")
    b = Enum.map(0..8, &"l#{&1}\n") ++ ["Y\n"]

    assert Diff.unified(a, b, "a/src/x", "b/src/x", 0) ==
             ~S"""
             --- a/src/x
             +++ b/src/x
             @@ -10 +10 @@
             -l9
             +Y
             """
  end

  test "splitlines/1 matches str.splitlines(keepends=True) for the shapes we read" do
    assert Diff.splitlines("") == []
    assert Diff.splitlines("a\n") == ["a\n"]
    assert Diff.splitlines("a\nb\n") == ["a\n", "b\n"]
    assert Diff.splitlines("a\nb") == ["a\n", "b"]
    assert Diff.splitlines("a\n\nb\n") == ["a\n", "\n", "b\n"]
  end
end
