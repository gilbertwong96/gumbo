defmodule Gumbo.SelectTreeConstructionTest do
  use ExUnit.Case, async: true

  alias Gumbo.Test.Html5lib

  @fixture Path.expand("../fixtures/html5lib-select-tree-construction.dat", __DIR__)
  @cases Html5lib.cases!(@fixture)
  @cases_count 18

  # Each case is upstream's document and upstream's expected tree, compared line by
  # line. The name is the document, so a failure says which case moved.
  #
  # What this gate is not: it does not cover 0007. Every select case upstream's
  # tree-construction file carries puts the `select` inside a `table` or a `td`, so a
  # scope query already stops at that cell and adding `select` to the scope types
  # changes nothing here — measured by taking `TAG(SELECT)` back out of the patched
  # copy and watching this file stay green. 0007's own shapes, and the injection that
  # fails them, are in `select_scope_test.exs`; the spec's cases for the relaxed parser
  # live in WPT's `customizable-select` tests, which need a browser harness rather than
  # this format.
  for test_case <- @cases do
    @test_case test_case

    test "html5lib: #{inspect(@test_case.data)}" do
      %{data: html, expected: expected} = @test_case
      assert Html5lib.render_document!(html) == expected
    end
  end

  # The fixture holds the select cases of upstream's files, not a copy of them. If a
  # rebase dropped one, the tests above would still pass while covering less.
  test "every select case the fixture was built with is here" do
    assert Enum.count_until(@cases, @cases_count + 1) == @cases_count
  end
end
