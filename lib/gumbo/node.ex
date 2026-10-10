defmodule Gumbo.Node do
  @moduledoc """
  A node in a parsed tree, identified by its index into the output's preorder
  node table.

  A node is only meaningful together with the `Gumbo.Output` handle it came
  from: the handle owns the tree and validates the index. Accessors arrive
  with the node API; `Gumbo.Output.document/1` and `Gumbo.Output.root/1` are
  the only constructors for now.
  """

  @enforce_keys [:output, :index]
  defstruct [:output, :index]

  @opaque t :: %__MODULE__{output: Gumbo.Output.t(), index: non_neg_integer()}
end
