defmodule Gumbo.Output do
  @moduledoc """
  The opaque result of `Gumbo.parse/2`.

  The struct holds one NIF resource — the parse tree, a private copy of the
  input, the options, and the preorder node table — plus the cached node
  count. Node structs returned by `document/1`, `root/1` and (in later
  tasks) the node accessors reference this handle; the handle must outlive
  them, and the tree is freed when the handle is garbage collected.
  """

  @enforce_keys [:resource, :node_count]
  defstruct [:resource, :node_count]

  @opaque t :: %__MODULE__{resource: reference(), node_count: non_neg_integer()}

  @doc """
  The document node (`GUMBO_NODE_DOCUMENT`), index 0 of the node table.
  """
  @spec document(t()) :: Gumbo.Node.t()
  def document(%__MODULE__{resource: resource} = output) do
    %Gumbo.Node{output: output, index: Gumbo.Native.output_document(resource)}
  end

  @doc """
  The root `<html>` element — real, or the implied one in fragment mode —
  index 1 of the node table.
  """
  @spec root(t()) :: Gumbo.Node.t()
  def root(%__MODULE__{resource: resource} = output) do
    %Gumbo.Node{output: output, index: Gumbo.Native.output_root(resource)}
  end

  @doc """
  The parse errors gumbo recorded, in source order; `[]` when none.

  These are descriptions of malformations the parser recovered from:
  `parse/2` still returns `{:ok, _}` with the best-effort tree. gumbo is
  designed to be resilient, so an empty list does not mean "valid HTML" —
  plenty of sloppy but legal markup produces no errors, and not every
  malformation produces one. The list is capped by the `:max_errors` option
  and by `:stop_on_first_error`.
  """
  @spec errors(t()) :: [Gumbo.Error.t()]
  def errors(%__MODULE__{resource: resource} = output) do
    resource
    |> Gumbo.Native.output_errors()
    |> Enum.map(&%Gumbo.Error{output: output, index: &1})
  end

  @doc "The exact input that was parsed."
  @spec input(t()) :: binary()
  def input(%__MODULE__{resource: resource}), do: Gumbo.Native.output_input(resource)

  @doc "The options the parse ran with, including the `:dirty` policy."
  @spec options(t()) :: Gumbo.Options.t()
  def options(%__MODULE__{resource: resource}) do
    struct(Gumbo.Options, Gumbo.Native.output_options(resource))
  end

  @doc "The number of nodes in the tree, document included."
  @spec node_count(t()) :: non_neg_integer()
  def node_count(%__MODULE__{node_count: node_count}), do: node_count
end
