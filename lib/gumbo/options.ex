defmodule Gumbo.Options do
  @moduledoc """
  Parser configuration for `Gumbo.parse/2`.

  Five fields map one-to-one onto gumbo's `GumboOptions`; `:dirty` is ours and
  controls scheduler dispatch rather than the parse itself. `new/1` validates
  every key against gumbo's documented ranges and rejects anything else with
  `{:error, {:invalid_option, key, value}}` before any work happens.
  """

  @dirty_threshold 20_480
  @max_buffer_size 4_294_967_295
  @c_int_max 2_147_483_647

  defstruct tab_stop: 8,
            stop_on_first_error: false,
            max_errors: -1,
            fragment_context: nil,
            fragment_namespace: :html,
            dirty: :auto

  @typedoc """
  `tab_stop`, `stop_on_first_error`, `max_errors`, `fragment_context` and
  `fragment_namespace` are `GumboOptions` fields; `:dirty` is this library's
  scheduler policy. `fragment_context` is `nil` (no fragment, gumbo's
  `GUMBO_TAG_LAST`) or a tag atom. `tab_stop` and `max_errors` are bounded by
  C `int` range, so a value that passes `new/1` can never fail the NIF
  decode.
  """
  @type t :: %__MODULE__{
          tab_stop: 1..2_147_483_647,
          stop_on_first_error: boolean(),
          max_errors: -1..2_147_483_647,
          fragment_context: nil | Gumbo.Tag.t(),
          fragment_namespace: Gumbo.Types.namespace(),
          dirty: :auto | boolean()
        }

  @doc """
  Returns the default options.

  ## Examples

      iex> Gumbo.Options.new().tab_stop
      8
  """
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Validates `opts` against gumbo's documented ranges and merges them over the
  defaults.

  An unknown key or an out-of-range value returns
  `{:error, {:invalid_option, key, value}}`.

  ## Examples

      iex> {:ok, options} = Gumbo.Options.new(max_errors: 3)
      iex> options.max_errors
      3

      iex> Gumbo.Options.new(bogus: 1)
      {:error, {:invalid_option, :bogus, 1}}
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) or is_map(opts) do
    Enum.reduce_while(opts, {:ok, %__MODULE__{}}, fn {key, value}, {:ok, acc} ->
      case validate_option(key, value) do
        :ok -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  @doc """
  Converts the struct to the map the NIF decodes.

  Every field is present, so the NIF can decode strictly.

  ## Examples

      iex> Gumbo.Options.to_nif(Gumbo.Options.new()) |> Map.keys() |> Enum.sort()
      [:dirty, :fragment_context, :fragment_namespace, :max_errors, :stop_on_first_error, :tab_stop]
  """
  @spec to_nif(t()) :: map()
  def to_nif(%__MODULE__{} = options) do
    %{
      tab_stop: options.tab_stop,
      stop_on_first_error: options.stop_on_first_error,
      max_errors: options.max_errors,
      fragment_context: options.fragment_context,
      fragment_namespace: options.fragment_namespace,
      dirty: options.dirty
    }
  end

  @doc """
  The single scheduler policy for `parse/2` and `materialize/2`: `:dirty` when
  forced, `:normal` when forbidden, and `:dirty` when `:auto` and the workload
  reaches `dirty_threshold/0`.

  ## Examples

      iex> Gumbo.Options.dispatch(Gumbo.Options.new(), 20_479)
      :normal

      iex> Gumbo.Options.dispatch(Gumbo.Options.new(), 20_480)
      :dirty

      iex> {:ok, forced} = Gumbo.Options.new(dirty: true)
      iex> Gumbo.Options.dispatch(forced, 1)
      :dirty
  """
  @spec dispatch(t(), non_neg_integer()) :: :normal | :dirty
  def dispatch(%__MODULE__{dirty: true}, _size), do: :dirty
  def dispatch(%__MODULE__{dirty: false}, _size), do: :normal
  def dispatch(%__MODULE__{dirty: :auto}, size) when size < @dirty_threshold, do: :normal
  def dispatch(%__MODULE__{dirty: :auto}, _size), do: :dirty

  @doc """
  The workload size at and above which `dispatch/2` picks `:dirty`.

  ## Examples

      iex> Gumbo.Options.dirty_threshold()
      20_480
  """
  @spec dirty_threshold() :: 20_480
  def dirty_threshold, do: @dirty_threshold

  # Public for testability even though `parse/2` is the only caller and calls
  # it before anything else: gumbo does not support buffers over 4 GB.
  @doc false
  @spec check_size(non_neg_integer()) :: :ok | {:error, :input_too_large}
  def check_size(size) when is_integer(size) and size >= 0 and size <= @max_buffer_size, do: :ok
  def check_size(_size), do: {:error, :input_too_large}

  defp validate_option(:tab_stop, value)
       when is_integer(value) and value >= 1 and value <= @c_int_max,
       do: :ok

  defp validate_option(:stop_on_first_error, value) when is_boolean(value), do: :ok

  defp validate_option(:max_errors, value)
       when is_integer(value) and value >= -1 and value <= @c_int_max,
       do: :ok

  defp validate_option(:fragment_context, nil), do: :ok

  defp validate_option(:fragment_context, value) when is_atom(value) do
    if value in Gumbo.Native.tag_all(), do: :ok, else: invalid(:fragment_context, value)
  end

  defp validate_option(:fragment_namespace, value) when value in [:html, :svg, :mathml], do: :ok
  defp validate_option(:dirty, value) when value in [:auto, true, false], do: :ok
  defp validate_option(key, value), do: invalid(key, value)

  defp invalid(key, value), do: {:error, {:invalid_option, key, value}}
end
