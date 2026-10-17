defmodule Gumbo.SpecialCategoryTest do
  use ExUnit.Case, async: true

  alias Gumbo.Output

  defp content!(html) do
    {:ok, output} = Gumbo.parse_fragment(html, :body)
    output |> Output.fragment_nodes() |> Gumbo.materialize(detail: :content)
  end

  # The spec's "special" category names `select`, and has since long before this pin:
  # WebKit's bug 44390 quotes the list in 2010 with `select` between `section` and
  # `style`, and the current standard still names it, between `section` and `source`.
  # The pinned base's `is_special_node` is a stale copy of that list — it jumps from
  # SECTION to STYLE — so an end tag with no matching open element walked past an open
  # select instead of stopping at it. Chrome, on the same bytes, gives this tree.
  test "an end tag option inside a select stops at the select" do
    assert [%{type: :element, tag: :option, children: children}] =
             content!("<option><select>x</option>y")

    assert [%{type: :element, tag: :select, children: select_children}] = children
    assert [%{type: :text, text: "xy"}] = select_children
  end

  # The shape reported from a reader's corpus: `</option>` used to take the option and
  # the select with it, which left everything written after it outside the select.
  test "the reported shape keeps the text the end tag used to move" do
    assert [%{type: :element, tag: :del, children: children}] =
             content!("<del><option><input><select>a</option>b")

    assert [
             %{
               type: :element,
               tag: :option,
               children: [
                 %{type: :element, tag: :input, children: []},
                 %{type: :element, tag: :select, children: [%{type: :text, text: "ab"}]}
               ]
             }
           ] = children
  end

  # The nested case is the one removal the old select parser kept, and this branch applies it in
  # the mode rather than through the special-category walk: the inner select closes the outer one,
  # which is why both texts land outside it. main keeps the inner select where it is, because the
  # marquee in between bounds the scope query its rules use instead.
  test "a nested select closes the one it sits in, marquee or not" do
    assert [
             %{type: :element, tag: :select, children: []},
             %{type: :text, text: "xy"}
           ] = content!("<select><marquee><i><select>x</select>y")
  end
end
