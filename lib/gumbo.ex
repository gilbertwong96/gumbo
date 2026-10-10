defmodule Gumbo do
  @moduledoc """
  HTML parsing on top of gumbo-parser 0.14.1.

  `parse/2` and `parse_fragment/3` return an opaque `Gumbo.Output` handle
  backed by a NIF resource: the tree stays native and is walked lazily
  through `Gumbo.Node` accessors. The handle holds a private copy of the
  input and is freed when it is garbage collected.
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

  @doc """
  Parses `html` as a fragment whose context element is `context`, returning a
  `Gumbo.Output` handle.

  Gumbo has no `gumbo_parse_fragment`: a fragment parse is
  `gumbo_parse_with_options` with `fragment_context` and `fragment_namespace`
  set, so this is a checked convenience wrapper over `parse/2` with those
  options.

  In fragment mode the output's root is a parser-inserted, implied `<html>`
  element — not the context element. The context element lives in gumbo's
  internal parser state and is freed with it, so it never appears in the
  returned tree; the parsed fragment is the children of that implied root,
  which is what `Gumbo.Output.fragment_nodes/1` returns.

  `context` sets `fragment_context`. `fragment_namespace` defaults to `:html`;
  a non-HTML namespace is how SVG and MathML fragments are requested — `:svg`
  with `fragment_namespace: :svg`, `:math` with `fragment_namespace: :mathml`.

  `context` implies the context element's namespace — `:svg` implies `:svg`,
  `:math` implies `:mathml`, and every other tag implies `:html` — and an
  `options` entry that disagrees is rejected rather than silently ignored:
  `fragment_context:` in `options` always conflicts (the positional argument
  sets it), and a `fragment_namespace:` that differs from the implied
  namespace returns `{:error, {:conflicting_option, key}}`. `Gumbo.parse/2`
  performs no such check; it is the unchecked path for combinations this
  function refuses.
  """
  @spec parse_fragment(binary(), Gumbo.Tag.t(), keyword()) ::
          {:ok, Gumbo.Output.t()} | {:error, term()}
  def parse_fragment(html, context, options \\ []) when is_binary(html) do
    with :ok <- check_fragment_conflicts(context, options) do
      parse(html, Keyword.put(options, :fragment_context, context))
    end
  end

  @doc """
  Like `parse_fragment/3`, but raises `ArgumentError` with the reason on
  failure.
  """
  @spec parse_fragment!(binary(), Gumbo.Tag.t(), keyword()) :: Gumbo.Output.t()
  def parse_fragment!(html, context, options \\ []) do
    case parse_fragment(html, context, options) do
      {:ok, output} -> output
      {:error, reason} -> raise ArgumentError, "cannot parse fragment: #{inspect(reason)}"
    end
  end

  defp check_fragment_conflicts(context, options) do
    cond do
      Keyword.has_key?(options, :fragment_context) ->
        {:error, {:conflicting_option, :fragment_context}}

      Keyword.get(options, :fragment_namespace) not in [nil, implied_namespace(context)] ->
        {:error, {:conflicting_option, :fragment_namespace}}

      true ->
        :ok
    end
  end

  defp implied_namespace(:svg), do: :svg
  defp implied_namespace(:math), do: :mathml
  defp implied_namespace(_context), do: :html
end
