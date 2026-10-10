defmodule Gumbo.Output do
  @moduledoc """
  The opaque result of `Gumbo.parse/2` and `Gumbo.parse_fragment/3`.

  The struct holds one NIF resource — the parse tree, a private copy of the
  input, the options, and the preorder node table — plus the cached node
  count. Node structs returned by `document/1`, `root/1`, `fragment_nodes/1`
  and the node accessors reference this handle; the handle must outlive
  them, and the tree is freed when the handle is garbage collected.
  """

  @enforce_keys [:resource, :node_count]
  defstruct [:resource, :node_count]

  @opaque t :: %__MODULE__{resource: reference(), node_count: non_neg_integer()}

  @doc """
  The document node (`GUMBO_NODE_DOCUMENT`), index 0 of the node table.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.type(Gumbo.Output.document(output))
      :document
  """
  @spec document(t()) :: Gumbo.Node.t()
  def document(%__MODULE__{resource: resource} = output) do
    %Gumbo.Node{output: output, index: Gumbo.Native.output_document(resource)}
  end

  @doc """
  The root `<html>` element — real, or the implied one in fragment mode —
  or `nil` when the parse stopped before any element was built.

  `stop_on_first_error: true` can halt the parse that early, and gumbo then
  has no root element (`output->root` stays NULL); the errors vector is
  exactly what a caller stopping on the first error wants, so the handle
  survives with no root rather than failing the parse.

  The root is also not necessarily node table index 1: a comment or
  processing instruction before `<html>` is a document child and occupies
  index 1 instead, so the index is resolved by pointer when the tree is
  built.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.tag(Gumbo.Output.root(output))
      :html

      iex> {:ok, output} = Gumbo.parse(String.duplicate("<div title=>", 50), stop_on_first_error: true)
      iex> Gumbo.Output.root(output)
      nil
  """
  @spec root(t()) :: Gumbo.Node.t() | nil
  def root(%__MODULE__{resource: resource} = output) do
    case Gumbo.Native.output_root(resource) do
      nil -> nil
      index -> %Gumbo.Node{output: output, index: index}
    end
  end

  @doc """
  The parse errors gumbo recorded, in source order; `[]` when none.

  These are descriptions of malformations the parser recovered from:
  `parse/2` still returns `{:ok, _}` with the best-effort tree. gumbo is
  designed to be resilient, so an empty list does not mean "valid HTML" —
  plenty of sloppy but legal markup produces no errors, and not every
  malformation produces one. The list is capped by the `:max_errors` option
  and by `:stop_on_first_error`.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Output.errors(output)
      []

      iex> {:ok, output} = Gumbo.parse(~s(<div class="a" class="b">))
      iex> output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.type()
      :duplicate_attr
  """
  @spec errors(t()) :: [Gumbo.Error.t()]
  def errors(%__MODULE__{resource: resource} = output) do
    resource
    |> Gumbo.Native.output_errors()
    |> Enum.map(&%Gumbo.Error{output: output, index: &1})
  end

  @doc """
  The exact input that was parsed.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<p>x</p>")
      iex> Gumbo.Output.input(output)
      "<p>x</p>"
  """
  @spec input(t()) :: binary()
  def input(%__MODULE__{resource: resource}), do: Gumbo.Native.output_input(resource)

  @doc """
  The options the parse ran with, including the `:dirty` policy.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<p>x</p>", max_errors: 3)
      iex> Gumbo.Output.options(output).max_errors
      3
  """
  @spec options(t()) :: Gumbo.Options.t()
  def options(%__MODULE__{resource: resource}) do
    struct(Gumbo.Options, Gumbo.Native.output_options(resource))
  end

  @doc """
  The number of nodes in the tree, document included.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Output.node_count(output)
      6
  """
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{node_count: node_count}), do: node_count

  @doc """
  The parsed fragment's nodes: the children of `root/1`.

  A fragment parse (`Gumbo.parse_fragment/3`) is a full
  `gumbo_parse_with_options` run, so its `root/1` is the parser-inserted
  implied `<html>` element rather than the context element — the context
  element lives in gumbo's internal parser state and is freed with it, so it
  never appears in the tree. The children of that implied root are the nodes
  the fragment parse produced, which is what callers almost always want.
  Outside fragment mode this is the children of the real `<html>` element.

  `[]` when `root/1` is `nil`: a `stop_on_first_error` parse that halted
  before any element was built has no root, so it has no fragment nodes.

  ## Examples

      iex> {:ok, output} = Gumbo.parse_fragment("<b>x</b>", :div)
      iex> Enum.map(Gumbo.Output.fragment_nodes(output), &Gumbo.Node.tag_name/1)
      ["b"]

      iex> {:ok, output} = Gumbo.parse(String.duplicate("<div title=>", 50), stop_on_first_error: true)
      iex> Gumbo.Output.fragment_nodes(output)
      []
  """
  @spec fragment_nodes(t()) :: [Gumbo.Node.t()]
  def fragment_nodes(%__MODULE__{} = output) do
    case root(output) do
      nil -> []
      root -> Gumbo.Node.children(root)
    end
  end
end
