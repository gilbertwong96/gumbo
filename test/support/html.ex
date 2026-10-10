defmodule Gumbo.Test.HTML do
  @doc "`<tag><tag>…</tag></tag>`, nested `n` deep."
  def nested(tag, n), do: String.duplicate("<#{tag}>", n) <> String.duplicate("</#{tag}>", n)
end
