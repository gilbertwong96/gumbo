defmodule Gumbo.NativeTest do
  use ExUnit.Case, async: true

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
end
