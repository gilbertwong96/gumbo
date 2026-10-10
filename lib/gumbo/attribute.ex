defmodule Gumbo.Attribute do
  @moduledoc """
  An attribute on an element node, identified by its index into the element's
  attribute vector.

  An attribute is only meaningful together with the `Gumbo.Node` it came
  from: the node's output handle owns the tree and validates both indices. A
  hand-built struct can carry an out-of-range node or attribute index; that
  is a programmer error, so the scalar accessors raise `ArgumentError` on one
  and `details/1` returns `{:error, :invalid_node}` or
  `{:error, :invalid_attribute}`. Nothing dereferences a bad index.
  """

  alias Gumbo.{Node, Output}

  @enforce_keys [:node, :index]
  defstruct [:node, :index]

  @opaque t :: %__MODULE__{node: Node.t(), index: non_neg_integer()}

  @doc "The attribute's namespace."
  @spec namespace(t()) :: Gumbo.Types.attribute_namespace()
  def namespace(%__MODULE__{} = attribute), do: fetch!(attribute, :namespace)

  @doc """
  The attribute's name, case-normalized by the tokenizer.

  In HTML content this is lowercased; foreign-content attributes are adjusted
  per the HTML spec, so e.g. `xlink:href` in SVG becomes `"href"` here with
  `namespace/1` `:xlink` — `original_name/1` keeps the source spelling.
  """
  @spec name(t()) :: binary()
  def name(%__MODULE__{} = attribute), do: fetch!(attribute, :name)

  @doc """
  The attribute's value after entity decoding, without surrounding quotes.

  Attributes with no value yield the empty binary.
  """
  @spec value(t()) :: binary()
  def value(%__MODULE__{} = attribute), do: fetch!(attribute, :value)

  @doc "The attribute name as written in the source."
  @spec original_name(t()) :: binary()
  def original_name(%__MODULE__{} = attribute), do: fetch!(attribute, :original_name)

  @doc """
  The attribute value as written in the source, including any surrounding
  quotes; the empty binary when the attribute has no value.
  """
  @spec original_value(t()) :: binary()
  def original_value(%__MODULE__{} = attribute), do: fetch!(attribute, :original_value)

  @doc "The source position where the attribute name starts."
  @spec name_start(t()) :: Gumbo.Position.t()
  def name_start(%__MODULE__{} = attribute), do: fetch!(attribute, :name_start)

  @doc "The source position just after the attribute name."
  @spec name_end(t()) :: Gumbo.Position.t()
  def name_end(%__MODULE__{} = attribute), do: fetch!(attribute, :name_end)

  @doc "The source position where the attribute value starts."
  @spec value_start(t()) :: Gumbo.Position.t()
  def value_start(%__MODULE__{} = attribute), do: fetch!(attribute, :value_start)

  @doc "The source position just after the attribute value."
  @spec value_end(t()) :: Gumbo.Position.t()
  def value_end(%__MODULE__{} = attribute), do: fetch!(attribute, :value_end)

  @doc """
  Every field at once, in one NIF crossing.

  The map keys are the accessor names above, so
  `details(attribute)[:name] == name(attribute)` for every key. The
  deliberate exception to the `ArgumentError` contract, matching
  `Gumbo.Node.details/1`: a caller asking for a whole attribute branches on
  `{:error, :invalid_node}` or `{:error, :invalid_attribute}` rather than
  rescues.
  """
  @spec details(t()) ::
          {:ok, map()} | {:error, :invalid_node | :invalid_attribute}
  def details(%__MODULE__{
        node: %Node{output: %Output{resource: resource}, index: node_index},
        index: attribute_index
      }) do
    Gumbo.Native.attr_details(resource, node_index, attribute_index)
  end

  # The scalar accessors project one field out of the details map, so a field
  # cannot disagree with details/1. The only other exits raise the
  # documented ArgumentError for whichever index is out of range.
  defp fetch!(
         %__MODULE__{
           node: %Node{output: %Output{resource: resource}, index: node_index},
           index: attribute_index
         },
         key
       ) do
    case Gumbo.Native.attr_details(resource, node_index, attribute_index) do
      {:ok, details} ->
        Map.fetch!(details, key)

      {:error, :invalid_node} ->
        raise ArgumentError, "invalid node index: #{node_index}"

      {:error, :invalid_attribute} ->
        raise ArgumentError, "invalid attribute index: #{attribute_index}"
    end
  end
end
