defmodule Gumbo.Position do
  @moduledoc """
  A source position into the parsed document.

  `line` and `column` are 1-based and `offset` is a 0-based byte offset into
  the input. Nodes gumbo inserted itself rather than found in the source —
  parser-inserted elements and the document node — carry the zeroed position
  `%Gumbo.Position{line: 0, column: 0, offset: 0}`, so 0 is legitimate for
  every field.
  """

  @enforce_keys [:line, :column, :offset]
  defstruct [:line, :column, :offset]

  @typedoc """
  A 1-based line/column pair (0 for parser-inserted nodes) plus a 0-based
  byte offset.
  """
  @type t :: %__MODULE__{
          line: non_neg_integer(),
          column: non_neg_integer(),
          offset: non_neg_integer()
        }
end
