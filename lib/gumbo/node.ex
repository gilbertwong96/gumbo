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

  @type t :: %__MODULE__{output: Gumbo.Output.t(), index: non_neg_integer()}

  @doc """
  The node's `t:Gumbo.Types.node_type/0`.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.type(Gumbo.Output.root(output))
      :element
  """
  @spec type(t()) :: Gumbo.Types.node_type()
  def type(%__MODULE__{} = node), do: fetch!(node, :type)

  @doc """
  The node's parent, or `nil` for the document node.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.parent(Gumbo.Output.document(output))
      nil

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.parent(Gumbo.Output.root(output)) |> Gumbo.Node.type()
      :document
  """
  @spec parent(t()) :: t() | nil
  def parent(%__MODULE__{output: output, index: index}) do
    wrap(output, Gumbo.Native.node_parent(output.resource, index))
  end

  @doc """
  The node's direct children in source order, or `[]` for leaves.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Enum.map(Gumbo.Node.children(Gumbo.Output.root(output)), &Gumbo.Node.type/1)
      [:element, :element]
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

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.next(p)
      nil
  """
  @spec next(t()) :: t() | nil
  def next(%__MODULE__{output: output, index: index}) do
    wrap(output, Gumbo.Native.node_next(output.resource, index))
  end

  @doc """
  The node's previous sibling, or `nil` when the node is first.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x<b>y</b></p>")
      iex> b = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "b"))
      iex> Gumbo.Node.previous(b) |> Gumbo.Node.type()
      :text
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

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Enum.map(Gumbo.Node.descendants(Gumbo.Output.root(output)), &Gumbo.Node.type/1)
      [:element, :element, :element, :element, :text]
  """
  @spec descendants(t()) :: [t()]
  def descendants(%__MODULE__{} = node), do: walk([], [node])

  @doc """
  The node's position within its parent's `children/1`, 0-based.

  `nil` for the document node and any other node gumbo never appended to a
  parent.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.index_within_parent(p)
      0

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.index_within_parent(Gumbo.Output.document(output))
      nil
  """
  @spec index_within_parent(t()) :: non_neg_integer() | nil
  def index_within_parent(%__MODULE__{} = node), do: fetch!(node, :index_within_parent)

  @doc """
  The parse flags gumbo recorded for this node's insertion.

  `[]` means `GUMBO_INSERTION_NORMAL`; parser-inserted nodes report why, e.g.
  `[:by_parser, :implied]` for an implied `<html>`.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.parse_flags(Gumbo.Output.root(output))
      [:by_parser, :implicit_end_tag, :implied]

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.parse_flags(p)
      []
  """
  @spec parse_flags(t()) :: [Gumbo.Types.parse_flag()]
  def parse_flags(%__MODULE__{} = node), do: fetch!(node, :parse_flags)

  @doc """
  Returns whether `flag` describes the node's insertion.

  `:normal` means no parse flags are set; any other flag tests its bit.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.parse_flag?(Gumbo.Output.root(output), :by_parser)
      true

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.parse_flag?(p, :normal)
      true
  """
  @spec parse_flag?(t(), Gumbo.Types.parse_flag()) :: boolean()
  def parse_flag?(%__MODULE__{} = node, :normal), do: parse_flags(node) == []
  def parse_flag?(%__MODULE__{} = node, flag), do: flag in parse_flags(node)

  @doc """
  The node's start position in the source.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.position(p)
      %Gumbo.Position{line: 1, column: 16, offset: 15}
  """
  @spec position(t()) :: Gumbo.Position.t()
  def position(%__MODULE__{} = node), do: fetch!(node, :position)

  @doc """
  Whether the document had an explicit doctype; `nil` off the document.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.has_doctype?(Gumbo.Output.document(output))
      true

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.has_doctype?(Gumbo.Output.root(output))
      nil
  """
  @spec has_doctype?(t()) :: boolean() | nil
  def has_doctype?(%__MODULE__{} = node), do: fetch!(node, :has_doctype)

  @doc """
  The doctype's name (lowercased by the tokenizer); `nil` without one.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.doctype_name(Gumbo.Output.document(output))
      "html"
  """
  @spec doctype_name(t()) :: binary() | nil
  def doctype_name(%__MODULE__{} = node), do: fetch!(node, :doctype_name)

  @doc """
  The doctype's public identifier, verbatim; `nil` when absent.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.public_identifier(Gumbo.Output.document(output))
      ""
  """
  @spec public_identifier(t()) :: binary() | nil
  def public_identifier(%__MODULE__{} = node), do: fetch!(node, :public_identifier)

  @doc """
  The doctype's system identifier, verbatim; `nil` when absent.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.system_identifier(Gumbo.Output.document(output))
      ""
  """
  @spec system_identifier(t()) :: binary() | nil
  def system_identifier(%__MODULE__{} = node), do: fetch!(node, :system_identifier)

  @doc """
  The document's quirks mode; `nil` off the document.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.quirks_mode(Gumbo.Output.document(output))
      :no_quirks
  """
  @spec quirks_mode(t()) :: Gumbo.Types.quirks_mode() | nil
  def quirks_mode(%__MODULE__{} = node), do: fetch!(node, :quirks_mode)

  @doc """
  The element's tag, `:unknown` for names outside gumbo's tag table; `nil`
  off elements.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<my-tag>x</my-tag>")
      iex> node = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag(&1) == :unknown))
      iex> Gumbo.Node.tag(node)
      :unknown
  """
  @spec tag(t()) :: Gumbo.Tag.t() | nil
  def tag(%__MODULE__{} = node), do: fetch!(node, :tag)

  @doc """
  The element's name as written, SVG case-corrected.

  For known tags this is gumbo's normalized name; for `:unknown` tags the
  name is recovered from `original_tag/1`. Parser-inserted elements have no
  source, so an `:unknown` tag there yields `nil`.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<my-tag>x</my-tag>")
      iex> node = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag(&1) == :unknown))
      iex> Gumbo.Node.tag_name(node)
      "my-tag"
  """
  @spec tag_name(t()) :: binary() | nil
  def tag_name(%__MODULE__{} = node), do: fetch!(node, :tag_name)

  @doc """
  The element's namespace; `nil` off elements.

  ## Examples

      iex> {:ok, output} = Gumbo.parse_fragment("<circle/>", :svg, fragment_namespace: :svg)
      iex> [circle] = Gumbo.Output.fragment_nodes(output)
      iex> Gumbo.Node.namespace(circle)
      :svg
  """
  @spec namespace(t()) :: Gumbo.Types.namespace() | nil
  def namespace(%__MODULE__{} = node), do: fetch!(node, :namespace)

  @doc """
  The element's attributes in source order; `[]` off elements.

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<p class="a" id="b">x</p>))
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> length(Gumbo.Node.attributes(p))
      2
  """
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

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<p class="a">x</p>))
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.attribute(p, "CLASS") |> Gumbo.Attribute.name()
      "class"
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

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<p class="a">x</p>))
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.attribute_map(p)
      %{"class" => "a"}
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

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<p class="a">x</p>))
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.original_tag(p)
      "<p class=\\"a\\">"
  """
  @spec original_tag(t()) :: binary() | nil
  def original_tag(%__MODULE__{} = node), do: fetch!(node, :original_tag)

  @doc """
  The end tag as written, including the `>`; the empty binary when the end
  tag was implied, `nil` off elements.

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<p class="a">x</p>))
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.original_end_tag(p)
      "</p>"
  """
  @spec original_end_tag(t()) :: binary() | nil
  def original_end_tag(%__MODULE__{} = node), do: fetch!(node, :original_end_tag)

  @doc """
  The element's end-tag position; `nil` off elements.

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<p class="a">x</p>))
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.end_position(p)
      %Gumbo.Position{line: 1, column: 15, offset: 14}
  """
  @spec end_position(t()) :: Gumbo.Position.t() | nil
  def end_position(%__MODULE__{} = node), do: fetch!(node, :end_position)

  @doc """
  The node's text after entity decoding; `nil` off text-like nodes.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.text(Enum.at(Gumbo.Node.children(p), 0))
      "x"
  """
  @spec text(t()) :: binary() | nil
  def text(%__MODULE__{} = node), do: fetch!(node, :text)

  @doc """
  The node's text as written in the source; `nil` off text-like nodes.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> p = output |> Gumbo.Output.root() |> Gumbo.Node.descendants() |> Enum.find(&(Gumbo.Node.tag_name(&1) == "p"))
      iex> Gumbo.Node.original_text(Enum.at(Gumbo.Node.children(p), 0))
      "x"
  """
  @spec original_text(t()) :: binary() | nil
  def original_text(%__MODULE__{} = node), do: fetch!(node, :original_text)

  @doc """
  Every field at once, in one NIF crossing.

  The map keys are the accessor names above, with `nil` for fields the node
  type does not carry, so `details(n)[:tag] == tag(n)` for every key. The
  deliberate exception to the `ArgumentError` contract: a caller asking for a
  whole node branches on `{:error, :invalid_node}` rather than rescues.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> {:ok, details} = Gumbo.Output.root(output) |> Gumbo.Node.details()
      iex> details[:type]
      :element
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
