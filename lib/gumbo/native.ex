defmodule Gumbo.Native do
  @moduledoc false

  @on_load :load_nif

  @spec smoke() :: binary()
  def smoke(), do: :erlang.nif_error(:nif_not_loaded)

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
  def tag_all(), do: :erlang.nif_error(:nif_not_loaded)

  @spec parse(binary(), map()) :: {:ok, reference()} | {:error, term()}
  def parse(_html, _options), do: :erlang.nif_error(:nif_not_loaded)

  @spec output_document(reference()) :: non_neg_integer()
  def output_document(_resource), do: :erlang.nif_error(:nif_not_loaded)

  @spec output_root(reference()) :: non_neg_integer()
  def output_root(_resource), do: :erlang.nif_error(:nif_not_loaded)

  @spec output_input(reference()) :: binary()
  def output_input(_resource), do: :erlang.nif_error(:nif_not_loaded)

  @spec output_node_count(reference()) :: non_neg_integer()
  def output_node_count(_resource), do: :erlang.nif_error(:nif_not_loaded)

  @spec output_options(reference()) :: map()
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
