defmodule Gumbo.Patches.Diff do
  @moduledoc """
  Unified diffs for the vendored-parser patch generators.

  A port of Python's `difflib.SequenceMatcher` and `difflib.unified_diff`,
  `autojunk` included. It exists for one reason: a regenerated `.patch` must be the
  same file the Python generators produced, byte for byte. A diff that is only
  *equivalent* would rewrite every patch the first time it ran, and those patches are
  both the build's input and the record of what each one changes and why.

  Only the parts `unified_diff` uses are ported, with the simplification that follows
  from our callers passing `isjunk = None`: nothing is junk, so the junk bookkeeping is
  absent and the loops of `find_longest_match` that extend a match over junk collapse
  into equality checks. `autojunk` is kept, because it is what makes difflib ignore
  lines appearing in more than 1% of a long file, and the vendored sources are long
  enough for it to matter.

  Each function names the difflib function it ports. The port is verified against the
  committed patches: regenerating them must reproduce the files byte for byte, and
  `make check-generators` fails when it does not.
  """

  @context 3

  @doc """
  The unified diff from `a` to `b`, rendered as `difflib.unified_diff` renders it:
  `---`/`+++` labels, then one `@@` hunk per change cluster, with `context` lines
  around each.

  Lines carry their terminators, as `splitlines(keepends=True)` gives them, so a final
  line without a newline stays without one. `splitlines/1` produces that shape.
  """
  @spec unified([binary()], [binary()], binary(), binary(), pos_integer()) :: binary()
  def unified(a, b, from_file, to_file, context \\ @context) do
    a = List.to_tuple(a)
    b = List.to_tuple(b)

    a
    |> grouped_opcodes(b, context)
    |> render(a, b, from_file, to_file)
    |> IO.iodata_to_binary()
  end

  @doc """
  Splits `text` into lines with their terminators, as `str.splitlines(keepends=True)`
  does.

  That function also breaks on `\\v`, `\\f`, `\\x1c`-`\\x1e`, `\\x85` and
  `\\u2028`/`\\u2029`, which this does not. The vendored C sources contain none of
  them, and the generators refuse to run when a file gains one rather than quietly
  producing a different diff.
  """
  @spec splitlines(binary()) :: [binary()]
  def splitlines(text) do
    case String.split(text, "\n") do
      [""] ->
        []

      parts ->
        case List.pop_at(parts, -1) do
          {"", rest} -> Enum.map(rest, &(&1 <> "\n"))
          {last, rest} -> Enum.map(rest, &(&1 <> "\n")) ++ [last]
        end
    end
  end

  ## difflib.unified_diff, difflib._format_range_unified ---------------------------

  defp render(groups, a, b, from_file, to_file) do
    {iodata, _} =
      Enum.reduce(groups, {[], true}, fn group, {acc, first?} ->
        header = if first?, do: ["--- ", from_file, "\n", "+++ ", to_file, "\n"], else: []
        first = hd(group)
        last = List.last(group)

        hunk = [
          "@@ -",
          format_range(elem(first, 1), elem(last, 2)),
          " +",
          format_range(elem(first, 3), elem(last, 4)),
          " @@\n"
        ]

        {[acc, header, hunk, body(group, a, b)], false}
      end)

    iodata
  end

  defp body(group, a, b) do
    Enum.map(group, fn
      {:equal, i1, i2, _, _} -> Enum.map(take(a, i1, i2), &[" ", &1])
      {:replace, i1, i2, j1, j2} -> [dash(a, i1, i2), plus(b, j1, j2)]
      {:delete, i1, i2, _, _} -> [dash(a, i1, i2)]
      {:insert, _, _, j1, j2} -> [plus(b, j1, j2)]
    end)
  end

  defp dash(a, i1, i2), do: Enum.map(take(a, i1, i2), &["-", &1])
  defp plus(b, j1, j2), do: Enum.map(take(b, j1, j2), &["+", &1])

  defp take(tuple, from, to) when to > from, do: for(i <- from..(to - 1)//1, do: elem(tuple, i))
  defp take(_tuple, _from, _to), do: []

  def format_range(start, stop) do
    beginning = start + 1
    length = stop - start

    cond do
      length == 1 -> "#{beginning}"
      length == 0 -> "#{beginning - 1},0"
      true -> "#{beginning},#{length}"
    end
  end

  ## difflib.SequenceMatcher.get_grouped_opcodes ----------------------------------

  def grouped_opcodes(a, b, n) do
    codes =
      case opcodes(a, b) do
        [] -> [{:equal, 0, 1, 0, 1}]
        codes -> codes
      end

    codes
    |> trim_first(n)
    |> trim_last(n)
    |> split(n, n + n, [], [])
  end

  defp trim_first([{:equal, i1, i2, j1, j2} | rest], n),
    do: [{:equal, max(i1, i2 - n), i2, max(j1, j2 - n), j2} | rest]

  defp trim_first(codes, _n), do: codes

  defp trim_last(codes, n) do
    case List.pop_at(codes, -1) do
      {{:equal, i1, i2, j1, j2}, rest} ->
        rest ++ [{:equal, i1, min(i2, i1 + n), j1, min(j2, j1 + n)}]

      _ ->
        codes
    end
  end

  defp split([], _n, _nn, group, groups) do
    groups =
      case Enum.reverse(group) do
        [] -> groups
        [{:equal, _, _, _, _}] -> groups
        closed -> [closed | groups]
      end

    Enum.reverse(groups)
  end

  defp split([{:equal, i1, i2, j1, j2} | rest], n, nn, group, groups) when i2 - i1 > nn do
    closed = Enum.reverse([{:equal, i1, min(i2, i1 + n), j1, min(j2, j1 + n)} | group])

    split(
      rest,
      n,
      nn,
      [{:equal, max(i1, i2 - n), i2, max(j1, j2 - n), j2}],
      [closed | groups]
    )
  end

  defp split([op | rest], n, nn, group, groups), do: split(rest, n, nn, [op | group], groups)

  ## difflib.SequenceMatcher.get_opcodes -------------------------------------------

  def opcodes(a, b) do
    a
    |> matching_blocks(b)
    |> Enum.reduce({0, 0, []}, fn {ai, bj, size}, {i, j, answer} ->
      answer =
        cond do
          i < ai and j < bj -> [{:replace, i, ai, j, bj} | answer]
          i < ai -> [{:delete, i, ai, j, bj} | answer]
          j < bj -> [{:insert, i, ai, j, bj} | answer]
          true -> answer
        end

      i = ai + size
      j = bj + size
      answer = if size > 0, do: [{:equal, ai, i, bj, j} | answer], else: answer

      {i, j, answer}
    end)
    |> elem(2)
    |> Enum.reverse()
  end

  ## difflib.SequenceMatcher.get_matching_blocks -----------------------------------

  def matching_blocks(a, b) do
    la = tuple_size(a)
    lb = tuple_size(b)
    index = index(b)

    [{0, la, 0, lb}]
    |> collect(a, b, index, [])
    |> Enum.sort()
    |> collapse()
    |> Kernel.++([{la, lb, 0}])
  end

  defp collect([], _a, _b, _index, acc), do: acc

  defp collect([{alo, ahi, blo, bhi} | queue], a, b, index, acc) do
    {i, j, k} = longest_match(a, b, index, alo, ahi, blo, bhi)

    if k > 0 do
      queue = if alo < i and blo < j, do: [{alo, i, blo, j} | queue], else: queue
      queue = if i + k < ahi and j + k < bhi, do: [{i + k, ahi, j + k, bhi} | queue], else: queue
      collect(queue, a, b, index, [{i, j, k} | acc])
    else
      collect(queue, a, b, index, acc)
    end
  end

  defp collapse(blocks) do
    {i1, j1, k1, out} = Enum.reduce(blocks, {0, 0, 0, []}, &collapse_step/2)

    Enum.reverse(flush(i1, j1, k1, out))
  end

  defp collapse_step({i2, j2, k2}, {i1, j1, k1, out}) do
    if i1 + k1 == i2 and j1 + k1 == j2 do
      {i1, j1, k1 + k2, out}
    else
      {i2, j2, k2, flush(i1, j1, k1, out)}
    end
  end

  defp flush(_i1, _j1, 0, out), do: out
  defp flush(i1, j1, k1, out), do: [{i1, j1, k1} | out]

  ## difflib.SequenceMatcher.find_longest_match, junk left out ---------------------

  def longest_match(a, b, index, alo, ahi, blo, bhi) do
    {besti, bestj, bestsize} =
      Enum.reduce(alo..(ahi - 1)//1, {alo, blo, 0, %{}}, fn i, {bi, bj, bs, j2len} ->
        {j2len, {bi, bj, bs}} =
          scan(Map.get(index, elem(a, i), []), j2len, i, blo, bhi, {bi, bj, bs})

        {bi, bj, bs, j2len}
      end)
      |> then(fn {bi, bj, bs, _j2len} -> {bi, bj, bs} end)

    extend_right(extend_left({besti, bestj, bestsize}, a, b, alo, blo), a, b, ahi, bhi)
  end

  defp scan(indices, j2len, i, blo, bhi, best) do
    Enum.reduce_while(indices, {%{}, best}, fn j, acc -> step(j, j2len, i, blo, bhi, acc) end)
  end

  defp step(j, _j2len, _i, blo, _bhi, acc) when j < blo, do: {:cont, acc}
  defp step(j, _j2len, _i, _blo, bhi, acc) when j >= bhi, do: {:halt, acc}

  defp step(j, j2len, i, _blo, _bhi, {newj2len, {bi, bj, bs}}) do
    k = Map.get(j2len, j - 1, 0) + 1
    newj2len = Map.put(newj2len, j, k)
    best = if k > bs, do: {i - k + 1, j - k + 1, k}, else: {bi, bj, bs}

    {:cont, {newj2len, best}}
  end

  ## difflib.SequenceMatcher._SequenceMatcher__chain_b, junk left out --------------

  def index(b) do
    n = tuple_size(b)

    b2j =
      0..(n - 1)
      |> Enum.reduce(%{}, fn i, acc -> Map.update(acc, elem(b, i), [i], &[i | &1]) end)
      |> Map.new(fn {line, idxs} -> {line, Enum.reverse(idxs)} end)

    if n >= 200 do
      ntest = div(n, 100) + 1
      Map.reject(b2j, fn {_line, idxs} -> length(idxs) > ntest end)
    else
      b2j
    end
  end

  defp extend_left({besti, bestj, bestsize}, a, b, alo, blo)
       when besti > alo and bestj > blo and elem(a, besti - 1) == elem(b, bestj - 1),
       do: extend_left({besti - 1, bestj - 1, bestsize + 1}, a, b, alo, blo)

  defp extend_left(result, _a, _b, _alo, _blo), do: result

  defp extend_right({besti, bestj, bestsize}, a, b, ahi, bhi)
       when besti + bestsize < ahi and bestj + bestsize < bhi and
              elem(a, besti + bestsize) == elem(b, bestj + bestsize),
       do: extend_right({besti, bestj, bestsize + 1}, a, b, ahi, bhi)

  defp extend_right(result, _a, _b, _ahi, _bhi), do: result
end
