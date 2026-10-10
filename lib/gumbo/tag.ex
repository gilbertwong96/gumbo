defmodule Gumbo.Tag do
  @moduledoc """
  The parse-free tag surface.

  `t/0` values are the atoms of gumbo's `GumboTag` enum, named after the
  normalized names gumbo itself reports (`:div`, `:"annotation-xml"`), with
  `:unknown` for `GUMBO_TAG_UNKNOWN`. Everything here goes straight to the
  corresponding `gumbo_*` helper; no parsing is involved.
  """

  @typedoc "A gumbo tag (`GumboTag`)."
  @type t :: atom()

  @doc """
  Returns the normalized name for `tag`, or `nil` if `tag` is not a tag.

  Out-of-range integers return `nil` instead of tripping the assert inside
  `gumbo_normalized_tagname`, which would abort the VM. `:unknown` returning
  `""` is gumbo's own behaviour — `GUMBO_TAG_UNKNOWN` normalizes to the empty
  string — and `Gumbo.Node.tag_name/1` is the accessor that returns a real
  name for unknown tags.

  ## Examples

      iex> Gumbo.Tag.name(:div)
      "div"

      iex> Gumbo.Tag.name(:unknown)
      ""

      iex> Gumbo.Tag.name(155)
      ""
  """
  @spec name(t()) :: binary() | nil
  def name(tag), do: Gumbo.Native.tag_name(tag)

  @doc """
  Converts a tag name back to its `t/0` value.

  Length-aware and case-insensitive, like `gumbo_tagn_enum`; unknown names
  become `:unknown`.

  ## Examples

      iex> Gumbo.Tag.from_name("DIV")
      :div

      iex> Gumbo.Tag.from_name("my-tag")
      :unknown
  """
  @spec from_name(binary()) :: t()
  def from_name(name), do: Gumbo.Native.tag_from_name(name)

  @doc """
  Returns whether `tag` is an HTML void element.

  ## Examples

      iex> Gumbo.Tag.void?(:br)
      true

      iex> Gumbo.Tag.void?(:div)
      false
  """
  @spec void?(t()) :: boolean()
  def void?(tag), do: Gumbo.Native.tag_void(tag)

  @doc """
  Returns the case-corrected name for an SVG tag, or `nil` when no
  replacement applies.

  ## Examples

      iex> Gumbo.Tag.svg_name("foreignObject")
      "foreignObject"

      iex> Gumbo.Tag.svg_name("circle")
      nil
  """
  @spec svg_name(binary()) :: binary() | nil
  def svg_name(name), do: Gumbo.Native.tag_svg_name(name)

  @doc """
  Extracts the tag name from a start or end tag, in original (source) case.

  Accepts exactly `<tagname>` and `</tagname>` with the trailing `>` — the
  shape the parser stores in `original_tag` and `original_end_tag` — and
  returns `{:error, :not_a_tag}` for anything else, including `"<>"` and
  `"</>"`, whose extracted name would be empty. Inputs that would trip
  `gumbo_tag_from_original_text`'s asserts never reach it.

  ## Examples

      iex> Gumbo.Tag.from_original_text("<my-tag data-a=1>")
      {:ok, "my-tag"}

      iex> Gumbo.Tag.from_original_text("my-tag")
      {:error, :not_a_tag}
  """
  @spec from_original_text(binary()) :: {:ok, binary()} | {:error, :not_a_tag}
  def from_original_text(text), do: Gumbo.Native.tag_from_original_text(text)

  @doc """
  Returns every tag in enum order, including `:unknown`.

  ## Examples

      iex> Enum.take(Gumbo.Tag.all(), 3)
      [:html, :head, :title]

      iex> Enum.take(Gumbo.Tag.all(), -1)
      [:unknown]
  """
  @spec all() :: [t()]
  def all(), do: Gumbo.Native.tag_all()
end
