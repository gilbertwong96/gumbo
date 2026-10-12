defmodule Gumbo.Native do
  @moduledoc false

  @on_load :load_nif

  @spec smoke() :: binary()
  def smoke, do: :erlang.nif_error(:nif_not_loaded)

  @spec tag_name(atom() | integer()) :: binary() | nil
  def tag_name(_tag), do: :erlang.nif_error(:nif_not_loaded)

  @spec tag_from_name(binary()) :: atom()
  def tag_from_name(_name), do: :erlang.nif_error(:nif_not_loaded)

  @spec tag_void(atom() | integer()) :: boolean()
  def tag_void(_tag), do: :erlang.nif_error(:nif_not_loaded)

  @spec tag_svg_name(binary()) :: binary() | nil
  def tag_svg_name(_name), do: :erlang.nif_error(:nif_not_loaded)

  @spec tag_from_original_text(binary()) :: {:ok, binary()} | {:error, :not_a_tag}
  def tag_from_original_text(_text), do: :erlang.nif_error(:nif_not_loaded)

  @spec tag_all() :: [atom()]
  def tag_all, do: :erlang.nif_error(:nif_not_loaded)

  @spec parse(binary(), map()) :: {:ok, reference()} | {:error, term()}
  def parse(_html, _options), do: :erlang.nif_error(:nif_not_loaded)

  @spec parse_dirty(binary(), map()) :: {:ok, reference()} | {:error, term()}
  def parse_dirty(_html, _options), do: :erlang.nif_error(:nif_not_loaded)

  @spec output_document(reference()) :: non_neg_integer() | {:error, :invalid_handle}
  def output_document(_resource), do: :erlang.nif_error(:nif_not_loaded)

  @spec output_root(reference()) :: non_neg_integer() | nil | {:error, :invalid_handle}
  def output_root(_resource), do: :erlang.nif_error(:nif_not_loaded)

  @spec output_input(reference()) :: binary() | {:error, :invalid_handle}
  def output_input(_resource), do: :erlang.nif_error(:nif_not_loaded)

  @spec output_node_count(reference()) :: non_neg_integer() | {:error, :invalid_handle}
  def output_node_count(_resource), do: :erlang.nif_error(:nif_not_loaded)

  @spec output_options(reference()) :: map() | {:error, :invalid_handle}
  def output_options(_resource), do: :erlang.nif_error(:nif_not_loaded)

  @spec node_details(reference(), non_neg_integer()) :: {:ok, map()} | {:error, :invalid_node}
  def node_details(_resource, _index), do: :erlang.nif_error(:nif_not_loaded)

  @spec node_children(reference(), non_neg_integer()) :: [non_neg_integer()]
  def node_children(_resource, _index), do: :erlang.nif_error(:nif_not_loaded)

  @spec node_parent(reference(), non_neg_integer()) :: non_neg_integer() | nil
  def node_parent(_resource, _index), do: :erlang.nif_error(:nif_not_loaded)

  @spec node_next(reference(), non_neg_integer()) :: non_neg_integer() | nil
  def node_next(_resource, _index), do: :erlang.nif_error(:nif_not_loaded)

  @spec node_previous(reference(), non_neg_integer()) :: non_neg_integer() | nil
  def node_previous(_resource, _index), do: :erlang.nif_error(:nif_not_loaded)

  @spec node_attributes(reference(), non_neg_integer()) :: [non_neg_integer()]
  def node_attributes(_resource, _index), do: :erlang.nif_error(:nif_not_loaded)

  @spec node_attribute(reference(), non_neg_integer(), binary()) :: non_neg_integer() | nil
  def node_attribute(_resource, _index, _name), do: :erlang.nif_error(:nif_not_loaded)

  @spec attr_details(reference(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, term()}
  def attr_details(_resource, _node_index, _attribute_index),
    do: :erlang.nif_error(:nif_not_loaded)

  @spec output_errors(reference()) :: [non_neg_integer()] | {:error, :invalid_handle}
  def output_errors(_resource), do: :erlang.nif_error(:nif_not_loaded)

  @spec error_details(reference(), non_neg_integer()) ::
          {:ok, map()} | {:error, :invalid_node}
  def error_details(_resource, _index), do: :erlang.nif_error(:nif_not_loaded)

  @spec materialize_output(reference(), non_neg_integer()) ::
          map() | {:error, :invalid_handle}
  def materialize_output(_resource, _detail), do: :erlang.nif_error(:nif_not_loaded)

  @spec materialize_output_dirty(reference(), non_neg_integer()) ::
          map() | {:error, :invalid_handle}
  def materialize_output_dirty(_resource, _detail),
    do: :erlang.nif_error(:nif_not_loaded)

  @spec materialize_node(reference(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, :invalid_node}
  def materialize_node(_resource, _index, _detail),
    do: :erlang.nif_error(:nif_not_loaded)

  @spec materialize_node_dirty(reference(), non_neg_integer(), non_neg_integer()) ::
          {:ok, map()} | {:error, :invalid_node}
  def materialize_node_dirty(_resource, _index, _detail),
    do: :erlang.nif_error(:nif_not_loaded)

  # The dispatch guard. Not a NIF: OTP 29 removed enif_have_dirty_schedulers
  # from the NIF API, so the VM-side query is the guard's body and this
  # keeps the call site in run/4 a plain function call.
  @spec dirty_schedulers?() :: boolean()
  def dirty_schedulers?, do: :erlang.system_info(:dirty_cpu_schedulers) > 0

  defp load_nif do
    path = :filename.join(:code.priv_dir(:gumbo), ~c"gumbo_nif")

    case :erlang.load_nif(path, 0) do
      :ok ->
        :ok

      {:error, reason} ->
        raise "failed to load NIF #{List.to_string(path)}.so: #{inspect(reason)}"
    end
  end
end
