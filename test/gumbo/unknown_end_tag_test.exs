defmodule Gumbo.UnknownEndTagTest do
  use ExUnit.Case, async: true

  # An unknown end tag that names no open element has to leave the stack alone:
  # the spec walks up the stack comparing tag *names*, and a custom element is not
  # in the special category, so the walk continues past it. The pin compares
  # GumboTag instead, and every unknown name is GUMBO_TAG_UNKNOWN, so any two
  # unknown names compare equal and the element one of them names is closed early —
  # the text that follows then leaves that element. Reported as
  # gilbertwong96/gumbo#3.
  #
  # This gate cannot come from html5lib's tree-construction corpus, and that is
  # measured rather than assumed: of its 1019 documents, four carry two distinct
  # unknown names and an unknown end tag at all, and all four are SVG/MathML,
  # which the foreign-content handler answers rather than this one. The cases
  # below are the ones this file has to carry itself.

  defp fragment(html) do
    {:ok, output} = Gumbo.parse_fragment(html, :body)

    output
    |> Gumbo.Output.fragment_nodes()
    |> Gumbo.materialize(detail: :content)
  end

  defp shapes(html), do: html |> fragment() |> Enum.map(&shape/1)

  # The fragment's text nodes in document order. A text node that left its element
  # shows up here as a different entry: `x` and `/div>` are one node while the
  # element stays open and two once something closed it.
  defp texts(html), do: html |> fragment() |> Enum.flat_map(&text_nodes/1)

  defp shape(%{type: :text, text: text}), do: {:text, text}

  defp shape(%{type: :element, children: children} = node),
    do: {:elem, name(node), Enum.map(children, &shape/1)}

  defp name(node), do: Map.get(node, :tag_name) || Atom.to_string(Map.fetch!(node, :tag))

  defp text_nodes(%{type: :text, text: text}), do: [text]

  defp text_nodes(%{type: :element, children: children}),
    do: Enum.flat_map(children, &text_nodes/1)

  test "the reported document keeps x and /div> in one text node" do
    assert shapes("<div>a<f&#igure dchment=\"{nope\">x</fidiv>/div>") == [
             {:elem, "div",
              [
                {:text, "a"},
                {:elem, "f&#igure", [{:text, "x/div>"}]}
              ]}
           ]

    assert texts("<div>a<f&#igure dchment=\"{nope\">x</fidiv>/div>") == ["a", "x/div>"]
  end

  test "an unknown end tag that names no open element is ignored" do
    assert texts("<foo>a</bar>b") == ["ab"]
    assert texts("<x-outer><y-inner>t</z-end>u") == ["tu"]

    assert shapes("<x-outer><y-inner>t</z-end>u") == [
             {:elem, "x-outer", [{:elem, "y-inner", [{:text, "tu"}]}]}
           ]

    # The shape the corpus case came from: broken custom-element markup inside a div.
    # Texts merge only inside one element, so the attachment's `xy` stays its own
    # entry while both characters stay in it.
    assert texts("<div>a<action-text-attachment>x</fidiv>y</div>") == ["a", "xy"]

    assert shapes("<div>a<action-text-attachment>x</fidiv>y</div>") == [
             {:elem, "div", [{:text, "a"}, {:elem, "action-text-attachment", [{:text, "xy"}]}]}
           ]
  end

  test "an unknown end tag that does name an open element still closes it" do
    assert shapes("<foo>a</foo>b") == [{:elem, "foo", [{:text, "a"}]}, {:text, "b"}]

    # Names are compared the way the tokenizer compares them, so case does not
    # decide this either.
    assert texts("<Foo>a</FOO>b") == ["a", "b"]
    assert texts("<x-outer><y-inner>t</y-INNER>u</x-outer>") == ["t", "u"]
  end

  test "an unknown end tag beside a known element is ignored, as it was" do
    assert texts("<div>a</fidiv>b") == ["ab"]
    assert texts("<span>a</mess>b") == ["ab"]
    assert texts("<div>a</xdiv>b") == ["ab"]
    assert texts("<div>a</span>b") == ["ab"]
  end
end
