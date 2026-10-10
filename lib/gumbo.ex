defmodule Gumbo do
  @moduledoc """
  HTML parsing on top of gumbo-parser 0.14.1.

  `parse/2` returns an opaque `Gumbo.Output` handle backed by a NIF resource:
  the tree stays native and is walked lazily through `Gumbo.Node` accessors.
  The handle holds a private copy of the input and is freed when it is
  garbage collected.
  """

  @doc """
  Parses `html` and returns a `Gumbo.Output` handle.

  `options` are validated by `Gumbo.Options.new/1`; an unknown key or an
  out-of-range value returns `{:error, {:invalid_option, key, value}}`.
  Buffers over 4 GB are rejected with `{:error, :input_too_large}`.
  """
  @spec parse(binary(), keyword()) :: {:ok, Gumbo.Output.t()} | {:error, term()}
  def parse(html, options \\ []) when is_binary(html) do
    with :ok <- Gumbo.Options.check_size(byte_size(html)),
         {:ok, opts} <- Gumbo.Options.new(options),
         {:ok, resource} <- Gumbo.Native.parse(html, Gumbo.Options.to_nif(opts)) do
      {:ok,
       %Gumbo.Output{
         resource: resource,
         node_count: Gumbo.Native.output_node_count(resource)
       }}
    end
  end

  @doc """
  Like `parse/2`, but raises `ArgumentError` with the reason on failure.
  """
  @spec parse!(binary(), keyword()) :: Gumbo.Output.t()
  def parse!(html, options \\ []) do
    case parse(html, options) do
      {:ok, output} -> output
      {:error, reason} -> raise ArgumentError, "cannot parse HTML: #{inspect(reason)}"
    end
  end
end
