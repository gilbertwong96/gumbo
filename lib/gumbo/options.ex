defmodule Gumbo.Options do
  @moduledoc """
  Parser configuration for `Gumbo.parse/2`.

  Five fields map one-to-one onto gumbo's `GumboOptions`; `:dirty` is ours and
  controls scheduler dispatch rather than the parse itself. `new/1` validates
  every key against gumbo's documented ranges and rejects anything else with
  `{:error, {:invalid_option, key, value}}` before any work happens.
  """

  @dirty_threshold 20_480

  # The largest input the NIF will parse, which the stack budget sets rather
  # than gumbo does. gumbo's own limit is far higher — an `int` buffer length,
  # 4 GiB - 1 — but the parse recurses on the input's nesting depth (gumbo
  # 0.14.1 caps it nowhere), so the C stack has to cover the worst case the
  # length can produce. A nested start tag costs at least 3 bytes, and the
  # deepest frame in that recursion is 64 bytes, so this cap needs
  # 16 MiB * 64 * 2 / 3 = 683 MiB of stack; see c_src/gumbo_parse_stack.c for
  # the measurements behind those numbers, and for the compile-time check that
  # the two constants still agree. The cap is where this library's own
  # regression corpus (an 11 MB document) and the HTML5 spec (~7 MB) both fit.
  @max_input_bytes 16_777_216

  # GumboOptions.max_errors, where -1 means uncapped. The default is bounded
  # rather than -1 because unbounded error recording is a memory hazard, not merely
  # a long list: gumbo records one error per unclosed element at EOF, and one per
  # unmatched end tag, and each of those used to carry a copy of the whole
  # open-element tag stack. Measured, 20 000 unclosed <div>s (100 KB of input)
  # produced 400 040 000 stack entries and 3.2 GB of allocation, and the same depth
  # followed by 20 000 </p> produced 6.4 GB — quadratic in the input, so no limit on
  # the input's length could bound it.
  #
  # c_src/patches/0003 now caps what one error keeps at its innermost 32 tags, so a
  # capped run holds at most C * 32 entries (100 * 32 = 3 200 today) rather than
  # C * depth. This default still decides how many errors a caller gets, and
  # `max_errors: -1` still lifts it for callers who want every error and will own
  # the cost: with the cap lifted, the error vector is linear in the input rather
  # than quadratic.
  @max_errors_default 100

  # GumboOptions.max_attributes, and the same convention: -1 for no cap. One element
  # used to be able to carry as many attributes as its bytes allowed, and deciding
  # whether a name was a duplicate was a scan of every attribute before it, so the
  # cost was the square of the count: 80 000 distinct names from 0.7 MB of input
  # measured 13.6 seconds (c_src/patches/0004 now indexes names, which makes that
  # linear, and this cap is what keeps the answer finite whether or not the index is
  # there). It is also the same lever Nokogiri's gumbo exposes as max_attributes,
  # with the same 1024. Exceeding it is refused rather than truncated, so a caller
  # never gets a tree that differs from what the pinned parser builds.
  @max_attributes_default 1024
  @c_int_max 2_147_483_647

  defstruct tab_stop: 8,
            stop_on_first_error: false,
            max_errors: @max_errors_default,
            max_attributes: @max_attributes_default,
            fragment_context: nil,
            fragment_namespace: :html,
            dirty: :auto

  @typedoc """
  `tab_stop`, `stop_on_first_error`, `max_errors`, `max_attributes`,
  `fragment_context` and `fragment_namespace` are `GumboOptions` fields; `:dirty`
  is this library's scheduler policy. `fragment_context` is `nil` (no fragment,
  gumbo's `GUMBO_TAG_LAST`) or a tag atom. `tab_stop`, `max_errors` and
  `max_attributes` are bounded by C `int` range, so a value that passes `new/1`
  can never fail the NIF decode. `max_errors` defaults to #{@max_errors_default} and
  `max_attributes` to #{@max_attributes_default} rather than to gumbo's "no cap";
  see the comments on the defaults for why, and pass -1 to either for no cap.
  """
  @type t :: %__MODULE__{
          tab_stop: 1..2_147_483_647,
          stop_on_first_error: boolean(),
          max_errors: -1..2_147_483_647,
          max_attributes: -1..2_147_483_647,
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
      [:dirty, :fragment_context, :fragment_namespace, :max_attributes, :max_errors, :stop_on_first_error, :tab_stop]
  """
  @spec to_nif(t()) :: map()
  def to_nif(%__MODULE__{} = options) do
    %{
      tab_stop: options.tab_stop,
      stop_on_first_error: options.stop_on_first_error,
      max_errors: options.max_errors,
      max_attributes: options.max_attributes,
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
  # it before anything else. The NIF checks the same limit again, so a caller
  # reaching the NIF directly cannot get past it into an unsized stack.
  @doc false
  @spec check_size(non_neg_integer()) :: :ok | {:error, :input_too_large}
  def check_size(size) when is_integer(size) and size >= 0 and size <= @max_input_bytes, do: :ok
  def check_size(_size), do: {:error, :input_too_large}

  defp validate_option(:tab_stop, value)
       when is_integer(value) and value >= 1 and value <= @c_int_max,
       do: :ok

  defp validate_option(:stop_on_first_error, value) when is_boolean(value), do: :ok

  defp validate_option(:max_errors, value)
       when is_integer(value) and value >= -1 and value <= @c_int_max,
       do: :ok

  defp validate_option(:max_attributes, value)
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
