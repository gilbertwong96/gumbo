defmodule Gumbo.Error do
  @moduledoc """
  A parse error gumbo recovered from.

  An error is only meaningful together with the `Gumbo.Output` handle it came
  from: the handle owns the error vector and validates the index. A
  hand-built struct can carry an out-of-range index; that is a programmer
  error, so the scalar accessors raise `ArgumentError` on one and `details/1`
  returns `{:error, :invalid_node}`. Nothing dereferences a bad index, and
  `nil` keeps exactly one meaning: this error type carries no such data.

  ## Accessors by error type

  Every error has a `type/1`, `position/1`, `original_text/1`, `message/1`
  and `caret/1`. The type-specific accessors return `nil` off their types:

  | Accessor | Error types |
  |---|---|
  | `codepoint/1` | `:utf8_invalid`, `:utf8_truncated`, `:control_character_in_input_stream`, `:noncharacter_in_input_stream`, `:numeric_char_ref_without_semicolon`, `:numeric_char_ref_invalid` |
  | `tokenizer/1` | the tokenizer-state errors (e.g. `:tag_eof`, `:attr_name_invalid`, `:comment_eof`, `:doctype_invalid`) |
  | `text/1` | `:named_char_ref_without_semicolon`, `:named_char_ref_invalid` |
  | `duplicate_attr/1` | `:duplicate_attr` |
  | `parser_error/1` | `:parser`, `:unacknowledged_self_closing_tag` |

  `original_text/1` is the source bytes from the error location to the end
  of the input; `message/1` is `gumbo_error_to_string` and `caret/1` is
  `gumbo_caret_diagnostic_to_string`, both rendered by gumbo itself against
  the retained copy of the source.
  """

  alias Gumbo.Output

  @enforce_keys [:output, :index]
  defstruct [:output, :index]

  @opaque t :: %__MODULE__{output: Output.t(), index: non_neg_integer()}

  @doc """
  The error's `t:Gumbo.Types.error_type/0`.

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<div class="a" class="b">))
      iex> output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.type()
      :duplicate_attr
  """
  @spec type(t()) :: Gumbo.Types.error_type()
  def type(%__MODULE__{} = error), do: fetch!(error, :type)

  @doc """
  The source position where the error occurred.

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<div class="a" class="b">))
      iex> output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.position()
      %Gumbo.Position{line: 1, column: 16, offset: 15}
  """
  @spec position(t()) :: Gumbo.Position.t()
  def position(%__MODULE__{} = error), do: fetch!(error, :position)

  @doc """
  The source bytes from the error location to the end of the input.

  gumbo stores a pointer to the offending byte, not a length, so the
  remainder of the retained input is what this accessor can report; for an
  error at end of input it is the empty binary.

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<div class="a" class="b">))
      iex> output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.original_text()
      "class=\\"b\\">"
  """
  @spec original_text(t()) :: binary()
  def original_text(%__MODULE__{} = error), do: fetch!(error, :original_text)

  @doc """
  Gumbo's own one-line description (`gumbo_error_to_string`).

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<div class="a" class="b">))
      iex> output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.message()
      "@1:16: Attribute class occurs multiple times, at positions 0 and 1."
  """
  @spec message(t()) :: binary()
  def message(%__MODULE__{} = error), do: fetch!(error, :message)

  @doc """
  Gumbo's caret diagnostic: the message, the offending source line, and a
  caret pointing at the column (`gumbo_caret_diagnostic_to_string`).

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<div class="a" class="b">))
      iex> output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.caret()
      "@1:16: Attribute class occurs multiple times, at positions 0 and 1.\\n<div class=\\"a\\" class=\\"b\\">\\n               ^\\n"
  """
  @spec caret(t()) :: binary()
  def caret(%__MODULE__{} = error), do: fetch!(error, :caret)

  @doc """
  The offending code point for the UTF-8 and numeric character-reference
  errors; `nil` off those types.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<p>" <> <<0xFF>> <> "</p>")
      iex> error = Enum.find(Gumbo.Output.errors(output), &(Gumbo.Error.type(&1) == :utf8_invalid))
      iex> Gumbo.Error.codepoint(error)
      255
  """
  @spec codepoint(t()) :: non_neg_integer() | nil
  def codepoint(%__MODULE__{} = error), do: fetch!(error, :codepoint)

  @doc """
  The tokenizer state and code point under the cursor for the tokenizer-
  state errors; `nil` off those types.

  `codepoint` is the raw value the tokenizer saw, so it can be `-1` at end
  of input.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<p a")
      iex> output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.tokenizer()
      %{state: :data, codepoint: -1}
  """
  @spec tokenizer(t()) ::
          %{state: Gumbo.Types.tokenizer_state(), codepoint: integer()} | nil
  def tokenizer(%__MODULE__{} = error), do: fetch!(error, :tokenizer)

  @doc """
  The named character reference as written for the named character-reference
  errors; `nil` off those types.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("&notit;")
      iex> output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.text()
      "not"
  """
  @spec text(t()) :: binary() | nil
  def text(%__MODULE__{} = error), do: fetch!(error, :text)

  @doc """
  The duplicated attribute's name and both of its indices in the attribute
  vector; `nil` off `:duplicate_attr`.

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<div class="a" class="b">))
      iex> output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.duplicate_attr()
      %{name: "class", new_index: 1, original_index: 0}
  """
  @spec duplicate_attr(t()) ::
          %{
            name: binary(),
            original_index: non_neg_integer(),
            new_index: non_neg_integer()
          }
          | nil
  def duplicate_attr(%__MODULE__{} = error), do: fetch!(error, :duplicate_attr)

  @doc """
  The parser state at the error for `:parser` and
  `:unacknowledged_self_closing_tag`; `nil` off those types.

  `tag_stack` is the stack of open elements at the error, bottom first, as
  `t:Gumbo.Tag.t/0` values.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("</p>")
      iex> output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.parser_error()
      %{input_type: :end_tag, input_tag: :p, insertion_mode: :initial, tag_stack: []}
  """
  @spec parser_error(t()) ::
          %{
            input_type: Gumbo.Types.token_type(),
            input_tag: Gumbo.Tag.t(),
            insertion_mode: Gumbo.Types.insertion_mode(),
            tag_stack: [Gumbo.Tag.t()]
          }
          | nil
  def parser_error(%__MODULE__{} = error), do: fetch!(error, :parser_error)

  @doc """
  Every field at once.

  The eight fields that read the error in place plus the two that render it,
  `message` and `caret`, so a caller wanting one field can ask for it without
  paying for the other nine.

  The map keys are the accessor names above, with `nil` for fields the error
  type does not carry, so `details(error)[:type] == type(error)` for every
  key. `Gumbo.materialize/2`'s error maps are this map minus `:caret`: it builds
  one map per error and a caret renders the whole source line, so see
  `caret/1` for that field on a single error. The deliberate exception to the
  `ArgumentError` contract, matching
  `Gumbo.Node.details/1`: a caller asking for a whole error branches on
  `{:error, :invalid_node}` rather than rescues.

  ## Examples

      iex> {:ok, output} = Gumbo.parse(~s(<div class="a" class="b">))
      iex> {:ok, details} = output |> Gumbo.Output.errors() |> Enum.at(0) |> Gumbo.Error.details()
      iex> details[:type]
      :duplicate_attr
  """
  @spec details(t()) :: {:ok, map()} | {:error, :invalid_node}
  def details(%__MODULE__{} = error) do
    with {:ok, fields} <- fields(error),
         {:ok, message} <- fetch_field(error, :message),
         {:ok, caret} <- fetch_field(error, :caret) do
      {:ok, Map.merge(fields, %{message: message, caret: caret})}
    end
  end

  # The eight fields that read the error in place. message and caret are
  # deliberately not among them: they render, and rendering is the whole cost
  # of a :parser error — print_message is variadic and print_tag_stack calls
  # it twice per open tag, so a 200-deep tag stack costs ~30us per render and
  # a caller asking only for the type must not pay it. Both surfaces still
  # come from the same extractors, so a field cannot disagree with details/1.
  defp fields(%__MODULE__{output: %Output{resource: resource}, index: index}),
    do: Gumbo.Native.error_fields(resource, index)

  # The only other exit raises the documented ArgumentError.
  defp fetch!(%__MODULE__{} = error, key) do
    case fetch_field(error, key) do
      {:ok, value} -> value
      {:error, :invalid_node} -> raise ArgumentError, "invalid error index: #{error.index}"
    end
  end

  defp fetch_field(%__MODULE__{output: %Output{resource: resource}, index: index}, :message),
    do: Gumbo.Native.error_message(resource, index)

  defp fetch_field(%__MODULE__{output: %Output{resource: resource}, index: index}, :caret),
    do: Gumbo.Native.error_caret(resource, index)

  defp fetch_field(%__MODULE__{} = error, key) do
    with {:ok, fields} <- fields(error), do: {:ok, Map.fetch!(fields, key)}
  end
end
