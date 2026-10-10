defmodule Gumbo.NativeTest do
  use ExUnit.Case, async: true

  test "the NIF loads and the vendored gumbo is linked" do
    assert Gumbo.Native.smoke() == "div"
  end
end
