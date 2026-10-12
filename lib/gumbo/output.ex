defmodule Gumbo.Output do
  @moduledoc """
  The opaque result of `Gumbo.parse/2` and `Gumbo.parse_fragment/3`.

  The struct holds one NIF resource — the parse tree, a private copy of the
  input, the options, and the preorder node table — plus the cached node
  count. Node structs returned by `document/1`, `root/1`, `fragment_nodes/1`
  and the node accessors reference this handle; the handle must outlive
  them, and the tree is freed when the handle is garbage collected.

  The struct is opaque but forgeable, and `resource` is not checked at
  construction: a hand-built struct can carry a non-resource term, and even
  a reference can be a stale one whose tree is gone. That is a programmer
  error, so every accessor that reads through the resource — `document/1`,
  `root/1`, `fragment_nodes/1`, `errors/1`, `input/1`, `options/1`, and
  `Gumbo.materialize/2` on an output — raises `ArgumentError` on it, exactly
  as the node accessors do on a forged index; the NIF-internal
  `{:error, :invalid_handle}` never reaches a caller. `node_count/1` reads
  only the cached struct field and does not raise.
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
  def document(%__MODULE__{} = output) do
    %Gumbo.Node{
      output: output,
      index: fetch_index!(Gumbo.Native.output_document(output.resource))
    }
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
  def root(%__MODULE__{} = output) do
    case fetch_handle!(output, &Gumbo.Native.output_root/1) do
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
  def errors(%__MODULE__{} = output) do
    output
    |> fetch_handle!(&Gumbo.Native.output_errors/1)
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
  def input(%__MODULE__{} = output), do: fetch_handle!(output, &Gumbo.Native.output_input/1)

  @doc """
  The options the parse ran with, including the `:dirty` policy.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<p>x</p>", max_errors: 3)
      iex> Gumbo.Output.options(output).max_errors
      3
  """
  @spec options(t()) :: Gumbo.Options.t()
  def options(%__MODULE__{} = output) do
    output
    |> fetch_handle!(&Gumbo.Native.output_options/1)
    |> then(&struct(Gumbo.Options, &1))
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

  # The index this returns lands in an opaque struct field, so the handle
  # check is specced for that one return type: routing the value through
  # fetch_handle!/2 hides the NIF's return type behind the fun's, and the
  # opaque in Gumbo.Node.t() then cannot be proven.
  @spec fetch_index!({:error, :invalid_handle} | non_neg_integer()) :: non_neg_integer()
  defp fetch_index!({:error, :invalid_handle}), do: raise(ArgumentError, "invalid output handle")
  defp fetch_index!(index), do: index

  # A forged or stale resource is a programmer error: the NIF answers
  # {:error, :invalid_handle} for both, and that internal tuple must not
  # reach a caller — not as a return value and not wrapped into a struct
  # field. The accessors raise ArgumentError like the node accessors do.
  defp fetch_handle!(%__MODULE__{resource: resource}, nif) do
    case nif.(resource) do
      {:error, :invalid_handle} -> raise ArgumentError, "invalid output handle"
      value -> value
    end
  end
end
