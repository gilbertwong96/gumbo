defmodule Gumbo.Node do
  @moduledoc """
  A node in a parsed tree, identified by its index into the output's preorder
  node table.

  A node is only meaningful together with the `Gumbo.Output` handle it came
  from: the handle owns the tree and validates the index. A hand-built struct
  can carry an out-of-range index; that is a programmer error, so the scalar
  accessors raise `ArgumentError` on one and `details/1` returns
  `{:error, :invalid_node}`. Nothing dereferences a bad index, and `nil`
  keeps exactly one meaning: this node type has no such field.

  ## Accessors by node type

  | Accessor | `:document` | `:element` / `:template` | text-like * |
  |---|---|---|---|
  | `type/1` `parent/1` `children/1` `next/1` `previous/1` `descendants/1` `index_within_parent/1` `parse_flags/1` `parse_flag?/2` `position/1` `details/1` | ✓ | ✓ | ✓ |
  | `has_doctype?/1` `doctype_name/1` `public_identifier/1` `system_identifier/1` `quirks_mode/1` | ✓ | `nil` | `nil` |
  | `tag/1` `tag_name/1` `namespace/1` `attributes/1` `attribute/2` `attribute_map/1` `original_tag/1` `original_end_tag/1` `end_position/1` | `nil` | ✓ | `nil` |
  | `text/1` `original_text/1` | `nil` | `nil` | ✓ |

  \\* `:text`, `:cdata`, `:comment`, `:whitespace`, `:processing_instruction`.

  `position/1` reports gumbo's `GumboSourcePosition` verbatim: `line` and
  `column` are 1-based, `column` counts characters while `offset` counts
  bytes. Parser-inserted elements carry the empty position (all zeros).
  """

  alias Gumbo.Output

  @enforce_keys [:output, :index]
  defstruct [:output, :index]

  @opaque t :: %__MODULE__{output: Gumbo.Output.t(), index: non_neg_integer()}

  @doc "The node's `Gumbo.Types.node_type/0`."
  @spec type(t()) :: Gumbo.Types.node_type()
  def type(%__MODULE__{} = node), do: fetch!(node, :type)

  @doc """
  The node's parent, or `nil` for the document node.
  """
  @spec parent(t()) :: t() | nil
  def parent(%__MODULE__{output: output, index: index}) do
    wrap(output, Gumbo.Native.node_parent(output.resource, index))
  end

  @doc """
  The node's direct children in source order, or `[]` for leaves.
  """
  @spec children(t()) :: [t()]
  def children(%__MODULE__{output: output, index: index}) do
    output.resource
    |> Gumbo.Native.node_children(index)
    |> Enum.map(&wrap(output, &1))
  end

  @doc """
  The node's next sibling, or `nil` when the node is last.

  Computed from the parent's children plus the node's
  `index_within_parent/1`; gumbo stores no sibling pointers.
  """
  @spec next(t()) :: t() | nil
  def next(%__MODULE__{output: output, index: index}) do
    wrap(output, Gumbo.Native.node_next(output.resource, index))
  end

  @doc """
  The node's previous sibling, or `nil` when the node is first.
  """
  @spec previous(t()) :: t() | nil
  def previous(%__MODULE__{output: output, index: index}) do
    wrap(output, Gumbo.Native.node_previous(output.resource, index))
  end

  @doc """
  The node and every node below it, in preorder.

  The walk is iterative — an explicit list used as a stack, one
  `children/1` call per node — so depth is bounded by memory, not by the
  scheduler's C stack.
  """
  @spec descendants(t()) :: [t()]
  def descendants(%__MODULE__{} = node), do: walk([], [node])

  @doc "The node's position within its parent's `children/1`, 0-based."
  @spec index_within_parent(t()) :: non_neg_integer()
  def index_within_parent(%__MODULE__{} = node), do: fetch!(node, :index_within_parent)

  @doc """
  The parse flags gumbo recorded for this node's insertion.

  `[]` means `GUMBO_INSERTION_NORMAL`; parser-inserted nodes report why, e.g.
  `[:by_parser, :implied]` for an implied `<html>`.
  """
  @spec parse_flags(t()) :: [Gumbo.Types.parse_flag()]
  def parse_flags(%__MODULE__{} = node), do: fetch!(node, :parse_flags)

  @doc """
  Returns whether `flag` describes the node's insertion.

  `:normal` means no parse flags are set; any other flag tests its bit.
  """
  @spec parse_flag?(t(), Gumbo.Types.parse_flag()) :: boolean()
  def parse_flag?(%__MODULE__{} = node, :normal), do: parse_flags(node) == []
  def parse_flag?(%__MODULE__{} = node, flag), do: flag in parse_flags(node)

  @doc "The node's start position in the source."
  @spec position(t()) :: Gumbo.Position.t()
  def position(%__MODULE__{} = node), do: fetch!(node, :position)

  @doc "Whether the document had an explicit doctype; `nil` off the document."
  @spec has_doctype?(t()) :: boolean() | nil
  def has_doctype?(%__MODULE__{} = node), do: fetch!(node, :has_doctype)

  @doc "The doctype's name (lowercased by the tokenizer); `nil` without one."
  @spec doctype_name(t()) :: binary() | nil
  def doctype_name(%__MODULE__{} = node), do: fetch!(node, :doctype_name)

  @doc "The doctype's public identifier, verbatim; `nil` when absent."
  @spec public_identifier(t()) :: binary() | nil
  def public_identifier(%__MODULE__{} = node), do: fetch!(node, :public_identifier)

  @doc "The doctype's system identifier, verbatim; `nil` when absent."
  @spec system_identifier(t()) :: binary() | nil
  def system_identifier(%__MODULE__{} = node), do: fetch!(node, :system_identifier)

  @doc "The document's quirks mode; `nil` off the document."
  @spec quirks_mode(t()) :: Gumbo.Types.quirks_mode() | nil
  def quirks_mode(%__MODULE__{} = node), do: fetch!(node, :quirks_mode)

  @doc """
  The element's tag, `:unknown` for names outside gumbo's tag table; `nil`
  off elements.
  """
  @spec tag(t()) :: Gumbo.Tag.t() | nil
  def tag(%__MODULE__{} = node), do: fetch!(node, :tag)

  @doc """
  The element's name as written, SVG case-corrected.

  For known tags this is gumbo's normalized name; for `:unknown` tags the
  name is recovered from `original_tag/1`. Parser-inserted elements have no
  source, so an `:unknown` tag there yields `nil`.
  """
  @spec tag_name(t()) :: binary() | nil
  def tag_name(%__MODULE__{} = node), do: fetch!(node, :tag_name)

  @doc "The element's namespace; `nil` off elements."
  @spec namespace(t()) :: Gumbo.Types.namespace() | nil
  def namespace(%__MODULE__{} = node), do: fetch!(node, :namespace)

  @doc "The element's attributes in source order; `[]` off elements."
  @spec attributes(t()) :: [Gumbo.Attribute.t()]
  def attributes(%__MODULE__{output: output, index: index} = node) do
    output.resource
    |> Gumbo.Native.node_attributes(index)
    |> Enum.map(&%Gumbo.Attribute{node: node, index: &1})
  end

  @doc """
  The element's attribute named `name`, matched case-insensitively exactly
  as `gumbo_get_attribute` does (`strcasecmp`); `nil` when absent or off
  elements.

  `name` must not contain a NUL byte: the search is a C-string comparison, so
  a NUL would silently truncate the lookup and could match a different
  attribute. A name containing one is rejected and `nil` is returned.
  """
  @spec attribute(t(), binary()) :: Gumbo.Attribute.t() | nil
  def attribute(%__MODULE__{output: output, index: index} = node, name) do
    case Gumbo.Native.node_attribute(output.resource, index, name) do
      nil -> nil
      attribute_index -> %Gumbo.Attribute{node: node, index: attribute_index}
    end
  end

  @doc """
  A name → value map of the element's attributes, built from the same data
  as `Gumbo.Attribute.details/1`.

  Lossy: the keys are the normalized names, so namespaces are folded away
  (an `xlink:href` and a plain `href` collide) and the map cannot represent
  duplicate names. `attributes/1` is the lossless path.
  """
  @spec attribute_map(t()) :: %{binary() => binary()}
  def attribute_map(%__MODULE__{} = node) do
    Map.new(attributes(node), fn attribute ->
      {:ok, details} = Gumbo.Attribute.details(attribute)
      {details.name, details.value}
    end)
  end

  @doc """
  The start tag as written, including the trailing `>`; the empty binary for
  parser-inserted elements, `nil` off elements.
  """
  @spec original_tag(t()) :: binary() | nil
  def original_tag(%__MODULE__{} = node), do: fetch!(node, :original_tag)

  @doc """
  The end tag as written, including the `>`; the empty binary when the end
  tag was implied, `nil` off elements.
  """
  @spec original_end_tag(t()) :: binary() | nil
  def original_end_tag(%__MODULE__{} = node), do: fetch!(node, :original_end_tag)

  @doc "The element's end-tag position; `nil` off elements."
  @spec end_position(t()) :: Gumbo.Position.t() | nil
  def end_position(%__MODULE__{} = node), do: fetch!(node, :end_position)

  @doc "The node's text after entity decoding; `nil` off text-like nodes."
  @spec text(t()) :: binary() | nil
  def text(%__MODULE__{} = node), do: fetch!(node, :text)

  @doc "The node's text as written in the source; `nil` off text-like nodes."
  @spec original_text(t()) :: binary() | nil
  def original_text(%__MODULE__{} = node), do: fetch!(node, :original_text)

  @doc """
  Every field at once, in one NIF crossing.

  The map keys are the accessor names above, with `nil` for fields the node
  type does not carry, so `details(n)[:tag] == tag(n)` for every key. The
  deliberate exception to the `ArgumentError` contract: a caller asking for a
  whole node branches on `{:error, :invalid_node}` rather than rescues.
  """
  @spec details(t()) :: {:ok, map()} | {:error, :invalid_node}
  def details(%__MODULE__{output: %Output{resource: resource}, index: index}) do
    Gumbo.Native.node_details(resource, index)
  end

  # The scalar accessors project one field out of the details map, so a field
  # cannot disagree with details/1. The only other exit raises the
  # documented ArgumentError.
  defp fetch!(%__MODULE__{output: %Output{resource: resource}, index: index}, key) do
    case Gumbo.Native.node_details(resource, index) do
      {:ok, details} -> Map.fetch!(details, key)
      {:error, :invalid_node} -> raise ArgumentError, "invalid node index: #{index}"
    end
  end

  defp wrap(%Output{} = output, index) when is_integer(index) do
    %__MODULE__{output: output, index: index}
  end

  defp wrap(%Output{}, nil), do: nil

  # Preorder with an explicit list used as a stack: the node is visited, its
  # children go on the front, and the accumulated list is reversed once.
  defp walk(acc, []), do: Enum.reverse(acc)
  defp walk(acc, [node | rest]), do: walk([node | acc], children(node) ++ rest)
end
