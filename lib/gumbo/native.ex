defmodule Gumbo.Native do
  @moduledoc false

  @on_load :load_nif

  @spec smoke() :: binary()
  def smoke(), do: :erlang.nif_error(:nif_not_loaded)

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
