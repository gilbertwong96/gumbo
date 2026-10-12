defmodule Gumbo.FaultPathsTest do
  use ExUnit.Case, async: false
  @moduletag :fault_paths

  # Each index is one extraction made to fail on purpose. A caller cannot tell an allocation
  # failure from a success unless the failure reaches it, so the assertion is that the call answers
  # the way it does for a forged handle: it raises. On the code this plan starts from it does not —
  # the failure term travels into the detail map, which cannot tell it from a term, and comes back
  # as 42 — and the assertion is what says so, by naming every index it happened at.
  test "an extraction that fails reaches the caller instead of a map with a hole in it" do
    {:ok, output} = Gumbo.parse(~s(<div a=1><p>x</p><!--c--></div>))
    document = Gumbo.Output.document(output)

    leaked =
      for n <- 1..64, reduce: [] do
        acc ->
          System.put_env("GUMBO_FAULT_AT", Integer.to_string(n))

          try do
            {:ok, details} = Gumbo.Node.details(document)

            # The hook fired somewhere in this call. If the failure reached the caller the rescue
            # below catches it; if it was swallowed, a field that is an atom on every node is now
            # whatever the failure value encodes as, and the assertion names the index.
            assert is_atom(details[:type]),
                   "extraction #{n} failed and came back as #{inspect(details[:type])}"

            acc
          rescue
            ArgumentError -> acc
          end
      end

    assert leaked == [],
           "these extractions failed without telling the caller: #{inspect(Enum.reverse(leaked))}"
  end
end
