defmodule Gumbo.FaultPathsTest do
  use ExUnit.Case, async: false
  @moduletag :fault_paths

  # An allocation failure is the only way the extractors in this NIF fail, and no test can cause
  # one, so this sweep causes it instead: GUMBO_FAULT_AT names the Nth extraction to make fail, and
  # each iteration parses again because that is what arms the hook.
  #
  # What is asserted is what a caller can see. A failure that reaches the caller comes back as a
  # raise; the same call with no failure comes back as a map. Anything else — an answer that
  # differs from the unarmed answer without raising — is a failure the caller was not told about,
  # and that is the finding this test exists to name, index by index.
  #
  # The first assertion is the canary, and it is the reason this file is not vacuous. Compiling the
  # hook out is not enough to trust a green run: it only says the hook cannot fire, not that this
  # was the fault build. A run against a library without the hook has no signal at all, and the
  # canary turns that into a failure that says so instead of a pass that means nothing.

  @sweep 1..64
  @html ~s(<div a=1><p>x</p><!--c--></div>)

  test "a failed extraction reaches the caller instead of becoming a value" do
    sentinel = fault_file() <> ".armed"
    File.rm(sentinel)
    {:returned, reference} = observe(@html)

    # The library that ran was a fault build: gumbo_fault_arm exists only in one, and it leaves this
    # file behind when a parse arms the hook. Everything below is satisfiable by a library with no
    # hook at all, which is not a hypothetical failure of this file.
    assert File.exists?(sentinel),
           """
           the library in this run has no fault hook, so every assertion below would pass without
           testing anything: it is not the one make check-fault-paths builds. Rebuild it and run
           this suite through that target rather than mix test.
           """

    outcomes =
      for n <- @sweep do
        File.write!(fault_file(), Integer.to_string(n))
        {n, observe(@html)}
      end

    # The hook fires somewhere in this run: some index either raised or answered differently from
    # the unarmed answer. Without this the assertions below are satisfied by a library whose hook
    # was compiled out, which is the one way this file could pass while testing nothing.
    assert Enum.any?(outcomes, fn
             {_n, {:raised, _}} -> true
             {_n, {:returned, observed}} -> observed != reference
           end),
           """
           no extraction failed in this run, so this sweep proves nothing: the hook is not in the
           library. It is compiled in only under -DGUMBO_TEST_FAULTS, which only make
           check-fault-paths passes, so run it through that target rather than mix test.
           """

    # The armed index really did fire somewhere in this run: some answer either raised or came
    # back different from the unarmed one. The sentinel above says the library has a hook; this
    # says the hook was reached, which a sweep that never read its index would not.
    assert Enum.any?(outcomes, fn
             {_n, {:raised, _}} -> true
             {_n, {:returned, observed}} -> observed != reference
           end),
           """
           no armed extraction changed this call's answer, so the sweep never fired: nothing here
           is being tested. The index is read from #{fault_file()}, and the library reads it at
           each parse.
           """

    # A swallowed failure is not required to look like a wrong type; it is required to look like
    # *something*, and every field this map carries has one exact value per node. So the test is
    # that the armed answer is either a raise or the unarmed answer.
    swallowed =
      for {n, {:returned, observed}} <- outcomes, observed != reference, do: n

    assert swallowed == [],
           "these extractions failed and the failure came back as a value instead of raising: " <>
             inspect(swallowed)
  end

  # The index lives in a file: the target compiles its path into the library, and a value written
  # here is what the next parse reads. The environment cannot carry it, because a running VM's
  # getenv does not follow System.put_env -- measured, and the reason this is a file.
  defp fault_file, do: System.fetch_env!("GUMBO_FAULT_FILE")

  # What is compared is the detail map and nothing else, because it is made of values derived from
  # the HTML and is therefore the same on every run: the node the map comes from is a handle, and
  # two handles for the same node are never equal, which is how a comparison against a reference
  # turns into a list of every index. A raise counts as told, so the exception type is not narrowed
  # -- an unexpected one still cannot make this test pass, since passing requires every armed answer
  # to carry the unarmed map.
  #
  # The parse materializes the tree through the same hooked extractor, and a failure swallowed there
  # is not visible in this map. That is deliberate: this sweep owns the detail map's path, and the
  # materialized path is what Task 2 converts to a return value and then covers.
  defp observe(html) do
    {:ok, output} = Gumbo.parse(html)
    {:ok, details} = Gumbo.Node.details(Gumbo.Output.document(output))

    {:returned, details}
  rescue
    error -> {:raised, error}
  end
end
