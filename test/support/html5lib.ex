defmodule Gumbo.Test.Html5lib do
  @moduledoc """
  Reads html5lib's tree-construction files and renders a parsed document in the same
  line format, so upstream's cases can be compared with this library directly.

  A case is a `#data` block, an `#errors` block and a `#document` block. Only the
  document text and the expected tree are read: `#errors` is upstream's parse-error
  log, and this library reports errors in its own shape, so comparing the two would
  be comparing something else.

  The tree format is one line per node — `| `, then two spaces per level, no closing
  tags, text in quotes — which is what html5lib's files carry. The renderer raises on
  anything it has not been taught, so a case that grows a node type cannot pass by
  being rendered as something it is not.
  """

  @doc """
  Reads every case in a tree-construction file, in file order.

  The markers are matched as whole lines, so prose in the file's header that happens to
  mention a `<select>` is not read as a case.
  """
  def cases!(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.reduce({[], nil}, &collect/2)
    |> then(fn {reversed, open} ->
      Enum.reverse(if open, do: [open | reversed], else: reversed)
    end)
    |> Enum.map(&finish!/1)
  end

  @doc """
  Parses a document and renders it the way html5lib's files write one.
  """
  def render_document!(html) do
    {:ok, output} = Gumbo.parse(html)
    output |> Gumbo.materialize(detail: :full) |> render_result!()
  end

  defp collect("#data", {cases, _open}), do: {cases, %{data: [], expected: [], part: :data}}
  defp collect("#errors", {cases, %{} = open}), do: {cases, %{open | part: :errors}}
  defp collect("#document", {cases, %{} = open}), do: {cases, %{open | part: :document}}
  defp collect("", {cases, %{part: :document} = open}), do: {[open | cases], nil}
  defp collect(line, {cases, open}), do: {cases, append(line, open)}

  defp append(_line, nil), do: nil
  defp append(_line, %{part: :errors} = open), do: open
  defp append(line, %{part: :data} = open), do: %{open | data: open.data ++ [line]}
  defp append(line, %{part: :document} = open), do: %{open | expected: open.expected ++ [line]}

  defp finish!(%{data: data, expected: expected}) do
    if data == [] do
      raise "a #data block with no document text"
    end

    stray = Enum.reject(expected, &(&1 == "" or String.starts_with?(&1, "|")))

    if stray != [] do
      raise "a #document block with a line that is neither blank nor a tree line: #{inspect(hd(stray))}"
    end

    %{
      data: Enum.join(data, "\n"),
      expected: expected |> Enum.filter(&(&1 != "")) |> Enum.join("\n")
    }
  end

  defp render_result!(%{document: document}) do
    lines = document[:children] |> List.wrap() |> Enum.flat_map(&node(&1, 0))

    # The doctype is named on the document rather than kept as a child node, so it is
    # written here — unless a child already carries it, or the document has none, which
    # must not be given a line for one.
    carries_it = Enum.any?(document[:children] || [], &(&1[:type] == :doctype))

    if document[:has_doctype] and not carries_it do
      Enum.join(doctype(document) ++ lines, "\n")
    else
      Enum.join(lines, "\n")
    end
  end

  defp doctype(document) do
    case document[:name] do
      nil -> raise "the document carries a doctype with no name"
      name -> ["| <!DOCTYPE #{name}>"]
    end
  end

  defp node(%{type: :doctype, name: name}, depth) when is_binary(name) do
    [indent(depth) <> "<!DOCTYPE #{name}>"]
  end

  defp node(%{type: :element, namespace: :html} = element, depth) do
    open = indent(depth) <> "<" <> element.tag_name <> attributes(element) <> ">"
    [open | Enum.flat_map(element.children, &node(&1, depth + 1))]
  end

  # A foreign element is written as `<namespace name>`, which is how html5lib's files
  # spell `<svg svg>`, `<svg g>` and `<math mi>`.
  defp node(%{type: :element, namespace: namespace} = element, depth)
       when namespace in [:svg, :mathml] do
    open = indent(depth) <> "<" <> foreign(namespace) <> " " <> element.tag_name <> ">"
    [open | Enum.flat_map(element.children, &node(&1, depth + 1))]
  end

  defp node(%{type: :text, text: text}, depth), do: [indent(depth) <> inspect(text)]
  defp node(%{type: :comment, text: text}, depth), do: [indent(depth) <> "<!-- #{text} -->"]

  defp node(other, _depth) do
    raise "this renderer has not been taught #{inspect(Map.take(other, [:type, :tag, :namespace]))}"
  end

  defp foreign(:svg), do: "svg"
  defp foreign(:mathml), do: "math"

  defp attributes(element) do
    Enum.map_join(element.attributes, fn attribute ->
      ~s( #{attribute.name}="#{attribute.value}")
    end)
  end

  defp indent(depth), do: "| " <> String.duplicate("  ", depth)
end
