defmodule Gumbo.SelectTreeConstructionTest do
  use ExUnit.Case, async: true

  alias Gumbo.Test.Html5lib

  @fixture Path.expand("../fixtures/html5lib-select-tree-construction.dat", __DIR__)
  @cases Html5lib.cases!(@fixture)
  @cases_count 18

  # Each case is upstream's document compared with a tree line by line, and the name is the
  # document, so a failure says which case moved.
  #
  # Six of the eighteen write an element inside the select, and those are the six the "in select"
  # mode this branch restores does not keep: upstream's tree (and main's parser, which follows the
  # current spec) holds the `math`, `svg` or `plaintext` element and its text; here the element is
  # a parse error and the token is dropped, so only its text merges with what follows it, and for
  # the `plaintext` case the tokenizer is never switched to PLAINTEXT either. Those six trees are
  # recorded below, the other twelve are compared with upstream's own file, and
  # NOKOGIRI-COMPAT.md says why the branch is the legacy side of this library.
  #
  # What this gate is not: it does not cover 0007. Every select case upstream's
  # tree-construction file carries puts the `select` inside a `table` or a `td`, so a
  # scope query already stops at that cell and adding `select` to the scope types
  # changes nothing here — measured by taking `TAG(SELECT)` back out of the patched
  # copy and watching this file stay green. 0007's own shapes, and the injection that
  # fails them, are in `select_scope_test.exs`; the spec's cases for the relaxed parser
  # live in WPT's `customizable-select` tests, which need a browser harness rather than
  # this format.
  @recorded %{
    "<!DOCTYPE html><body><table><tr><td><select><math><mi>foo</mi><mi>bar</mi><p>baz</table><p>quux" =>
      ~S"""
      | <!DOCTYPE html>
      | <html>
      |   <head>
      |   <body>
      |     <table>
      |       <tbody>
      |         <tr>
      |           <td>
      |             <select>
      |               "foobarbaz"
      |     <p>
      |       "quux"
      """,
    "<!DOCTYPE html><body><table><select><math><mi>foo</mi><mi>bar</mi><p>baz</table><p>quux" =>
      ~S"""
      | <!DOCTYPE html>
      | <html>
      |   <head>
      |   <body>
      |     <select>
      |       "foobarbaz"
      |     <table>
      |     <p>
      |       "quux"
      """,
    "<!DOCTYPE html><body><table><tr><td><select><svg><g>foo</g><g>bar</g><p>baz</table><p>quux" =>
      ~S"""
      | <!DOCTYPE html>
      | <html>
      |   <head>
      |   <body>
      |     <table>
      |       <tbody>
      |         <tr>
      |           <td>
      |             <select>
      |               "foobarbaz"
      |     <p>
      |       "quux"
      """,
    "<!DOCTYPE html><body><table><select><svg><g>foo</g><g>bar</g><p>baz</table><p>quux" => ~S"""
    | <!DOCTYPE html>
    | <html>
    |   <head>
    |   <body>
    |     <select>
    |       "foobarbaz"
    |     <table>
    |     <p>
    |       "quux"
    """,
    "<!doctype html><select><plaintext></plaintext>X" => ~S"""
    | <!DOCTYPE html>
    | <html>
    |   <head>
    |   <body>
    |     <select>
    |       "X"
    """,
    "<!doctype html><table><select><plaintext>a<caption>b" => ~S"""
    | <!DOCTYPE html>
    | <html>
    |   <head>
    |   <body>
    |     <select>
    |       "a"
    |     <table>
    |       <caption>
    |         "b"
    """
  }

  # The trees above are heredocs, so each carries the newline before its terminator and the
  # renderer's text does not.
  @moved Map.new(@recorded, fn {data, tree} -> {data, String.replace_suffix(tree, "\n", "")} end)

  for test_case <- @cases do
    @test_case test_case

    test "html5lib: #{inspect(@test_case.data)}" do
      %{data: html, expected: expected} = @test_case
      assert Html5lib.render_document!(html) == Map.get(@moved, html, expected)
    end
  end

  # The fixture holds the select cases of upstream's files, not a copy of them. If a
  # rebase dropped one, the tests above would still pass while covering less.
  test "every select case the fixture was built with is here" do
    assert Enum.count_until(@cases, @cases_count + 1) == @cases_count
  end

  # Every recorded tree belongs to a case in the fixture: an upstream rename would otherwise leave
  # a tree here compared with nothing while the case fell back to upstream's expectation.
  test "every recorded tree belongs to a fixture case" do
    assert Map.keys(@moved) -- Enum.map(@cases, & &1.data) == []
  end
end
