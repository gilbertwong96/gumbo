defmodule Gumbo.Html5libTest do
  use ExUnit.Case, async: true

  alias Gumbo.Test.Html5lib

  # The reader and the renderer are the gate's own machinery, so what they refuse
  # matters as much as what they accept: a case they cannot represent has to fail
  # loudly rather than be compared as something it is not.
  test "a document block line that is neither blank nor a tree line is refused" do
    path = fixture("#data\n<p>x\n#errors\n\n#document\n| <html>\nnot a tree line\n\n")

    assert_raise RuntimeError, ~r/neither blank nor a tree line/, fn -> Html5lib.cases!(path) end
  end

  test "a data block with no document text is refused" do
    path = fixture("#data\n#errors\n\n#document\n| <html>\n\n")

    assert_raise RuntimeError, ~r/no document text/, fn -> Html5lib.cases!(path) end
  end

  test "a node the renderer has not been taught is refused, not written as something else" do
    assert_raise RuntimeError, ~r/not been taught/, fn ->
      Html5lib.render_document!("<?pi x?>")
    end
  end

  test "a document without a doctype gets no line for one" do
    assert Html5lib.render_document!("<p>x</p>") ==
             "| <html>\n|   <head>\n|   <body>\n|     <p>\n|       \"x\""
  end

  defp fixture(contents) do
    path = Path.join(System.tmp_dir!(), "html5lib-#{System.unique_integer([:positive])}.dat")
    File.write!(path, contents)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
