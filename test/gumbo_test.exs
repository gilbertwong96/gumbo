defmodule GumboTest do
  use ExUnit.Case
  doctest Gumbo

  test "greets the world" do
    assert Gumbo.hello() == :world
  end
end
