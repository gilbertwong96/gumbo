defmodule Gumbo.NativeTest do
  use ExUnit.Case, async: true

  # The uncovered lines in this module are the pre-load stubs, which the NIF
  # replaces at load time. Asserting they ran would mean breaking the build;
  # asserting they were *replaced* is the invariant that matters, and it is
  # the one a forgotten export trips. Every declared function needs an entry
  # here: :output marks the position of a real parse's handle, which only
  # exists at test time, and assert_loaded/3 substitutes it. The stub bodies
  # are invisible to :cover — the NIF replaces them before any call — so this
  # module's coverage percentage is not evidence about this test.
  @calls [
    smoke: [],
    tag_name: [:div],
    tag_from_name: ["div"],
    tag_void: [:div],
    tag_svg_name: ["svg"],
    tag_from_original_text: ["<my-tag data-a=1>"],
    tag_all: [],
    parse: ["<div>x</div>", Gumbo.Options.to_nif(Gumbo.Options.new())],
    parse_dirty: ["<div>x</div>", Gumbo.Options.to_nif(Gumbo.Options.new())],
    output_document: [:output],
    output_root: [:output],
    output_input: [:output],
    output_node_count: [:output],
    output_options: [:output],
    node_details: [:output, 0],
    node_children: [:output, 0],
    node_parent: [:output, 0],
    node_next: [:output, 0],
    node_previous: [:output, 0],
    node_attributes: [:output, 0],
    node_attribute: [:output, 0, "id"],
    attr_details: [:output, 0, 0],
    output_errors: [:output],
    error_fields: [:output, 0],
    error_message: [:output, 0],
    error_caret: [:output, 0],
    materialize_output: [:output, 0],
    materialize_output_dirty: [:output, 0],
    materialize_node: [:output, 0, 0],
    materialize_node_dirty: [:output, 0, 0],
    dirty_schedulers?: []
  ]

  test "the NIF loads and the vendored gumbo is linked" do
    assert Gumbo.Native.smoke() == "div"
  end

  # Review Focus 5: a hook that could fire in a build that did not ask for it would make a real
  # allocation failure look like a test failure. This build has no GUMBO_TEST_FAULTS, so its library
  # has no arm and no hook, and the file the fault sweep writes is simply a file the parser never
  # reads. The path is the one a fault build is compiled with, and the default when it is not.
  test "the fault hook is inert in a build that did not ask for it" do
    fault_file = "/tmp/gumbo-fault-at"
    File.write!(fault_file, "1")

    on_exit(fn -> File.rm(fault_file) end)

    {:ok, output} = Gumbo.parse(~s(<div class="a" id="b">x</div>))

    assert Gumbo.Node.type(Gumbo.Output.document(output)) == :document

    assert output |> Gumbo.Output.document() |> Gumbo.Node.children() |> length() == 1
  end

  test "every function the module declares is loaded, not a stub" do
    declared =
      Gumbo.Native.__info__(:functions)
      |> Enum.reject(&(&1 in [module_info: 0, module_info: 1]))

    callable = Enum.map(@calls, fn {name, args} -> {name, length(args)} end)
    missing = Enum.sort(declared) -- Enum.sort(callable)
    stale = Enum.sort(callable) -- Enum.sort(declared)

    assert Enum.sort(declared) == Enum.sort(callable),
           "a new Native function needs an entry in @calls: #{inspect(missing)}; " <>
             "no function for: #{inspect(stale)}"

    {:ok, output} = Gumbo.parse("<div><p>x</p></div>")

    for {name, args} <- @calls do
      assert_loaded(name, args, output)
    end
  end

  defp assert_loaded(name, args, output) do
    args =
      Enum.map(args, fn
        :output -> output.resource
        arg -> arg
      end)

    apply(Gumbo.Native, name, args)
  rescue
    e in ErlangError ->
      if e.original == :nif_not_loaded do
        flunk("#{name}/#{length(args)} is still the pre-load stub: the NIF does not export it")
      else
        reraise e, __STACKTRACE__
      end
  end
end
