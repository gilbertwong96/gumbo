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
  Inputs over 16 MiB are rejected with `{:error, :input_too_large}`: the
  parse recurses on the input's nesting depth, so the C stack is sized from
  the input's length, and that limit is where the reservation stays
  reasonable. An element with more than `:max_attributes` attributes (1024 by
  default) is rejected with `{:error, :too_many_attributes}` rather than having
  the extra attributes dropped, because a tree missing attributes would be one
  this library's fidelity claim does not cover. A document past `:max_tree_depth`
  open elements (no limit by default) is rejected with `{:error, :tree_too_deep}`
  rather than handed back truncated, for the same reason. A document that runs the parse out
  of the C stack it was given is rejected with `{:error, :too_deep}`: the stack is
  sized from the input's length, so this is a backstop under the arithmetic rather
  than a limit a caller has to think about.

  Parses of 20 KiB or more (`Gumbo.Options.dirty_threshold/0` bytes) run
  on a dirty CPU scheduler so a large document does not block a normal
  scheduler; `dirty: false` forces the normal scheduler, `dirty: true`
  the dirty one. On a VM without dirty schedulers the dirty choice falls
  back to the normal path invisibly.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.Node.type(Gumbo.Output.root(output))
      :element
  """
  @spec parse(binary(), keyword()) :: {:ok, Gumbo.Output.t()} | {:error, term()}
  def parse(html, options \\ []) when is_binary(html) do
    with :ok <- Gumbo.Options.check_size(byte_size(html)),
         {:ok, opts} <- Gumbo.Options.new(options),
         {:ok, resource} <-
           run(
             fn -> Gumbo.Native.parse(html, Gumbo.Options.to_nif(opts)) end,
             fn -> Gumbo.Native.parse_dirty(html, Gumbo.Options.to_nif(opts)) end,
             opts,
             byte_size(html)
           ) do
      {:ok,
       %Gumbo.Output{
         resource: resource,
         node_count: Gumbo.Native.output_node_count(resource)
       }}
    end
  end

  @doc """
  Like `parse/2`, but raises `ArgumentError` with the reason on failure.

  ## Examples

      iex> Gumbo.parse!("<!doctype html><p>x</p>") |> Gumbo.Output.node_count()
      6
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

  ## Examples

      iex> {:ok, output} = Gumbo.parse_fragment("<b>x</b>", :div)
      iex> Enum.map(Gumbo.Output.fragment_nodes(output), &Gumbo.Node.tag_name/1)
      ["b"]

      iex> Gumbo.parse_fragment("<b>x</b>", :div, fragment_namespace: :svg)
      {:error, {:conflicting_option, :fragment_namespace}}
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

  ## Examples

      iex> Gumbo.parse_fragment!("<b>x</b>", :div) |> Gumbo.Output.fragment_nodes() |> Enum.map(&Gumbo.Node.tag_name/1)
      ["b"]
  """
  @spec parse_fragment!(binary(), Gumbo.Tag.t(), keyword()) :: Gumbo.Output.t()
  def parse_fragment!(html, context, options \\ []) do
    case parse_fragment(html, context, options) do
      {:ok, output} -> output
      {:error, reason} -> raise ArgumentError, "cannot parse fragment: #{inspect(reason)}"
    end
  end

  @doc """
  Converts a handle, a node, a list of nodes, or `nil` into plain nested
  Elixir data in a single NIF call.

  The walk is iterative in C — the node table is preorder, and each node's
  map is built from its already-built children in one reverse pass — so
  depth is bounded by memory, not by the scheduler's C stack.

  `Gumbo.Output.t()` materializes to `%{document: ..., root: ..., errors:
  [...]}`, `Gumbo.Node.t()` to that node's map, a list to the list of its
  nodes' maps, and `nil` to `nil`. `root` is `nil` for a
  `stop_on_first_error` parse that halted before any element was built —
  that handle has no root, only errors.

  `detail: :full` (the default) carries every gumbo field, with `nil` where
  the node type has none; `detail: :content` returns a usable tree without
  the source bookkeeping (positions, originals, flags and index) — except that
  an element whose tag is `:unknown` also carries `tag_name`, because its atom
  is the one thing that cannot name it, and a processing instruction also
  carries `target` and `data`,
  the two parts the spec gives that payload. The
  materialized `:full` values agree with the lazy accessors — they come
  from the same extractors — under the materialized shape's own key names
  (`start_position`, `name`).

  `detail:` is validated here and raises `ArgumentError` for anything but
  `:full | :content`.

  Like `parse/2`, materializations of 20 480 nodes or more run on a dirty
  CPU scheduler — the size proxy is the handle's cached node count, so the
  dispatch costs no NIF call — with the same `dirty:` override; it raises
  `ArgumentError` for anything but `:auto | true | false`.

  ## Examples

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.materialize(output) |> Map.keys() |> Enum.sort()
      [:document, :errors, :root]

      iex> {:ok, output} = Gumbo.parse("<!doctype html><p>x</p>")
      iex> Gumbo.materialize(output, detail: :content)[:root][:tag]
      :html
  """
  @spec materialize(
          Gumbo.Output.t() | Gumbo.Node.t() | [Gumbo.Node.t()] | nil,
          keyword()
        ) :: term()
  def materialize(value, options \\ []) do
    detail = detail_code(options)
    dispatch = dispatch_options(options)
    do_materialize(value, detail, dispatch)
  end

  defp do_materialize(nil, _detail, _dispatch), do: nil

  defp do_materialize(values, detail, dispatch) when is_list(values),
    do: Enum.map(values, &do_materialize(&1, detail, dispatch))

  defp do_materialize(%Gumbo.Node{output: output, index: index}, detail, dispatch) do
    result =
      run(
        fn -> Gumbo.Native.materialize_node(output.resource, index, detail) end,
        fn -> Gumbo.Native.materialize_node_dirty(output.resource, index, detail) end,
        dispatch,
        output.node_count
      )

    case result do
      {:ok, map} -> map
      {:error, _reason} = error -> error
    end
  end

  defp do_materialize(%Gumbo.Output{resource: resource, node_count: node_count}, detail, dispatch) do
    case run(
           fn -> Gumbo.Native.materialize_output(resource, detail) end,
           fn -> Gumbo.Native.materialize_output_dirty(resource, detail) end,
           dispatch,
           node_count
         ) do
      map when is_map(map) -> map
      {:error, :invalid_handle} -> raise ArgumentError, "invalid output handle"
    end
  end

  defp detail_code(options) do
    case Keyword.get(options, :detail, :full) do
      :full -> 0
      :content -> 1
      other -> raise ArgumentError, "invalid detail: #{inspect(other)}"
    end
  end

  defp dispatch_options(options) do
    case Gumbo.Options.new(Keyword.take(options, [:dirty])) do
      {:ok, dispatch} ->
        dispatch

      {:error, {:invalid_option, :dirty, value}} ->
        raise ArgumentError, "invalid dirty: #{inspect(value)}"
    end
  end

  defp run(normal_fun, dirty_fun, options, size) do
    case Gumbo.Options.dispatch(options, size) do
      :dirty ->
        if Gumbo.Native.dirty_schedulers?(), do: dirty_fun.(), else: normal_fun.()

      :normal ->
        normal_fun.()
    end
  end

  defp check_fragment_conflicts(context, options) do
    with :ok <- validate_fragment_namespace(options) do
      cond do
        Keyword.has_key?(options, :fragment_context) ->
          {:error, {:conflicting_option, :fragment_context}}

        Keyword.get(options, :fragment_namespace) not in [nil, implied_namespace(context)] ->
          {:error, {:conflicting_option, :fragment_namespace}}

        true ->
          :ok
      end
    end
  end

  # fragment_namespace is validated here, before the agreement check, so an
  # invalid value is reported as {:invalid_option, key, value} — as parse/2
  # would — instead of being mislabeled as a conflict. Reusing Options.new/1
  # keeps the two paths from ever disagreeing on what is valid.
  defp validate_fragment_namespace(options) do
    case Keyword.fetch(options, :fragment_namespace) do
      :error ->
        :ok

      {:ok, value} ->
        case Gumbo.Options.new(fragment_namespace: value) do
          {:ok, _opts} -> :ok
          {:error, _reason} = error -> error
        end
    end
  end

  defp implied_namespace(:svg), do: :svg
  defp implied_namespace(:math), do: :mathml
  defp implied_namespace(_context), do: :html
end
