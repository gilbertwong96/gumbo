defmodule Gumbo.Test.HTML do
  @doc "`<tag><tag>…</tag></tag>`, nested `n` deep."
  def nested(tag, n), do: String.duplicate("<#{tag}>", n) <> String.duplicate("</#{tag}>", n)

  @doc """
  Wraps `inner` in the doctype/html/body wrapper the shape matrix is
  generated and measured against: `<!doctype html><html><body>…</body></html>`.
  """
  def wrapped(inner), do: "<!doctype html><html><body>" <> inner <> "</body></html>"

  @doc """
  The tree depth below `node`: the number of edges on the longest path to a
  leaf. Iterative — an explicit stack — so it is safe on 20 000-deep trees
  where a recursive helper would be its own stack problem.
  """
  @spec depth(Gumbo.Node.t()) :: non_neg_integer()
  def depth(node), do: do_depth([{node, 0}], 0)

  defp do_depth([], best), do: best

  defp do_depth([{node, depth} | rest], best) do
    children = Gumbo.Node.children(node)
    do_depth(Enum.map(children, &{&1, depth + 1}) ++ rest, max(best, depth))
  end

  @doc """
  The depth below a materialized `:full` node map, iterative like `depth/1`.
  """
  @spec materialized_depth(map()) :: non_neg_integer()
  def materialized_depth(node), do: do_materialized_depth([{node, 0}], 0)

  defp do_materialized_depth([], best), do: best

  defp do_materialized_depth([{node, depth} | rest], best) do
    children = node[:children]
    do_materialized_depth(Enum.map(children, &{&1, depth + 1}) ++ rest, max(best, depth))
  end
end
