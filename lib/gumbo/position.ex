defmodule Gumbo.Position do
  @moduledoc """
  A source position into the parsed document.

  `line` and `column` are 1-based; `offset` is a 0-based byte offset into the
  input.
  """

  @enforce_keys [:line, :column, :offset]
  defstruct [:line, :column, :offset]

  @typedoc "A 1-based line/column pair plus a 0-based byte offset."
  @type t :: %__MODULE__{
          line: pos_integer(),
          column: pos_integer(),
          offset: non_neg_integer()
        }
end
