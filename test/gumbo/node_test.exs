defmodule Gumbo.NodeTest do
  use ExUnit.Case, async: true

  alias Gumbo.{Node, Output}

  defp parse!(html) do
    {:ok, output} = Gumbo.parse(html)
    output
  end

  defp descendants(output), do: output |> Output.root() |> Node.descendants()

  @details_keys ~w(type index_within_parent parse_flags position has_doctype doctype_name public_identifier system_identifier quirks_mode tag tag_name namespace original_tag original_end_tag end_position text original_text)a

  test "an out-of-range index is an error, never a dereference" do
    {:ok, output} = Gumbo.parse("<p>x</p>")
    forged = %Gumbo.Node{output: output, index: 10_000_000}
    assert {:error, :invalid_node} = Gumbo.Node.details(forged)
    assert_raise ArgumentError, fn -> Gumbo.Node.children(forged) end
    assert_raise ArgumentError, fn -> Gumbo.Node.type(forged) end
  end

  test "every node-reference accessor raises on a forged index" do
    {:ok, output} = Gumbo.parse("<p>x</p>")
    forged = %Gumbo.Node{output: output, index: 10_000_000}

    assert_raise ArgumentError, fn -> Node.parent(forged) end
    assert_raise ArgumentError, fn -> Node.next(forged) end
    assert_raise ArgumentError, fn -> Node.previous(forged) end
    assert_raise ArgumentError, fn -> Node.index_within_parent(forged) end
    assert_raise ArgumentError, fn -> Node.parse_flags(forged) end
    assert_raise ArgumentError, fn -> Node.position(forged) end
    assert_raise ArgumentError, fn -> Node.tag(forged) end
    assert_raise ArgumentError, fn -> Node.text(forged) end
  end

  test "column counts characters while offset counts bytes" do
    # Both documents put the second <p> nine bytes in for the multibyte case and
    # eight for the ASCII one: é is one character in two bytes, so the wider
    # document's byte offset is larger while its column is the same.
    {:ok, wide} = Gumbo.parse("<p>é</p><p>second</p>")
    {:ok, ascii} = Gumbo.parse("<p>a</p><p>second</p>")

    second_p = fn output ->
      output
      |> Gumbo.Output.root()
      |> Gumbo.Node.descendants()
      |> Enum.filter(&(Gumbo.Node.tag(&1) == :p))
      |> List.last()
    end

    wide_pos = Gumbo.Node.position(second_p.(wide))
    ascii_pos = Gumbo.Node.position(second_p.(ascii))

    assert wide_pos.offset == ascii_pos.offset + 1
    assert wide_pos.column == ascii_pos.column
  end

  test "tag_name/1 resolves a custom tag through original_tag" do
    {:ok, output} = Gumbo.parse("<my-tag>x</my-tag>")

    node =
      Gumbo.Output.root(output)
      |> Gumbo.Node.descendants()
      |> Enum.find(&(Gumbo.Node.tag(&1) == :unknown))

    assert Gumbo.Node.tag_name(node) == "my-tag"
  end

  test "tag_name/1 case-corrects SVG tags, known and unknown" do
    output = parse!("<svg><foreignobject>a</foreignobject><clippath>b</clippath></svg>")

    foreign = descendants(output) |> Enum.find(&(Node.tag(&1) == :foreignobject))
    assert Node.namespace(foreign) == :svg
    assert Node.tag_name(foreign) == "foreignObject"

    clip = descendants(output) |> Enum.find(&(Node.tag(&1) == :unknown))
    assert Node.namespace(clip) == :svg
    assert Node.original_tag(clip) == "<clippath>"
    assert Node.tag_name(clip) == "clipPath"
  end

  test "descendants/1 is iterative and preorder" do
    {:ok, output} = Gumbo.parse(Gumbo.Test.HTML.nested("span", 20_000))
    assert length(Gumbo.Node.descendants(Gumbo.Output.document(output))) >= 20_002
  end

  test "descendants/1 visits nodes in preorder" do
    output = parse!("<div><p>a</p><p>b</p></div>")

    indices =
      output
      |> Output.document()
      |> Node.descendants()
      |> Enum.map(& &1.index)

    assert indices == Enum.sort(indices)
  end

  test "parse_flags/1 is [] for a normal element and non-empty for an implied one" do
    # The <html> root is parser-implied here (no explicit <html> in the
    # source), which is the case the assertion is after.
    {:ok, output} = Gumbo.parse("<p>x</p>")
    assert Gumbo.Node.parse_flags(Gumbo.Output.root(output)) != []

    p = descendants(output) |> Enum.find(&(Node.tag(&1) == :p))
    assert Gumbo.Node.parse_flags(p) == []
  end

  test "parse_flag?/2 matches the flags parse_flags/1 reports" do
    output = parse!("<p>x</p>")
    root = Output.root(output)

    assert Node.parse_flags(root) == [:by_parser, :implicit_end_tag, :implied]
    assert Node.parse_flag?(root, :by_parser)
    assert Node.parse_flag?(root, :implied)
    assert Node.parse_flag?(root, :implicit_end_tag)
    refute Node.parse_flag?(root, :foster_parented)
    refute Node.parse_flag?(root, :normal)

    p = descendants(output) |> Enum.find(&(Node.tag(&1) == :p))
    assert Node.parse_flags(p) == []
    assert Node.parse_flag?(p, :normal)
    refute Node.parse_flag?(p, :implied)
  end

  test "parent/children/next/previous reflect the tree structure" do
    output = parse!("<ul><li>one</li><li>two</li></ul>")
    document = Output.document(output)
    html = Output.root(output)
    ul = descendants(output) |> Enum.find(&(Node.tag(&1) == :ul))
    [first, second] = Node.children(ul)

    assert Node.parent(html) == document
    assert Node.parent(document) == nil
    assert Node.children(document) == [html]
    assert Node.index_within_parent(html) == 0

    assert Node.children(ul) == [first, second]
    assert Node.parent(first) == ul
    assert Node.parent(second) == ul
    assert Node.index_within_parent(first) == 0
    assert Node.index_within_parent(second) == 1
    assert Node.next(first) == second
    assert Node.previous(second) == first
    assert Node.next(second) == nil
    assert Node.previous(first) == nil
    assert Node.next(ul) == nil
    assert Node.previous(ul) == nil

    text = Enum.find(Node.children(first), &(Node.type(&1) == :text))
    assert Node.children(text) == []
    assert Node.parent(text) == first
  end

  test "document: doctype accessors are populated and other accessors are nil" do
    output =
      parse!(
        ~s(<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd"><html><body><p>x</p></body></html>)
      )

    document = Output.document(output)

    assert Node.type(document) == :document
    assert Node.has_doctype?(document) == true
    assert Node.doctype_name(document) == "html"
    assert Node.public_identifier(document) == "-//W3C//DTD HTML 4.01//EN"
    assert Node.system_identifier(document) == "http://www.w3.org/TR/html4/strict.dtd"
    assert Node.quirks_mode(document) == :no_quirks

    assert Node.tag(document) == nil
    assert Node.tag_name(document) == nil
    assert Node.namespace(document) == nil
    assert Node.original_tag(document) == nil
    assert Node.original_end_tag(document) == nil
    assert Node.end_position(document) == nil
    assert Node.text(document) == nil
    assert Node.original_text(document) == nil
  end

  test "document without a doctype: has_doctype? is false and names are empty" do
    # gumbo normalizes absent doctype strings to the empty string for API
    # uniformity (parser.c: "if the doctype still has nulls, convert them to
    # empty strings"), so the fields are populated but blank.
    output = parse!("<p>x</p>")
    document = Output.document(output)

    assert Node.has_doctype?(document) == false
    assert Node.doctype_name(document) == ""
    assert Node.public_identifier(document) == ""
    assert Node.system_identifier(document) == ""
    assert Node.quirks_mode(document) == :quirks
  end

  test "element: element accessors are populated and other accessors are nil" do
    output = parse!(~s(<div class="x">hello</div>))
    div = descendants(output) |> Enum.find(&(Node.tag(&1) == :div))

    assert Node.type(div) == :element
    assert Node.tag(div) == :div
    assert Node.tag_name(div) == "div"
    assert Node.namespace(div) == :html
    assert Node.original_tag(div) == ~s(<div class="x">)
    assert Node.original_end_tag(div) == "</div>"
    assert %Gumbo.Position{} = Node.position(div)
    assert %Gumbo.Position{} = Node.end_position(div)

    assert Node.has_doctype?(div) == nil
    assert Node.doctype_name(div) == nil
    assert Node.public_identifier(div) == nil
    assert Node.system_identifier(div) == nil
    assert Node.quirks_mode(div) == nil
    assert Node.text(div) == nil
    assert Node.original_text(div) == nil
  end

  test "void element: original_end_tag is the empty binary" do
    output = parse!("<p>a<br>b</p>")
    br = descendants(output) |> Enum.find(&(Node.tag(&1) == :br))

    assert Node.original_tag(br) == "<br>"
    assert Node.original_end_tag(br) == ""
    assert %Gumbo.Position{} = Node.end_position(br)
  end

  test "template: element accessors are populated" do
    output = parse!("<template><p>x</p></template>")
    template = descendants(output) |> Enum.find(&(Node.type(&1) == :template))

    assert Node.type(template) == :template
    assert Node.tag(template) == :template
    assert Node.tag_name(template) == "template"
    assert Node.namespace(template) == :html
    assert Node.original_tag(template) == "<template>"
    assert Node.original_end_tag(template) == "</template>"
    assert Node.text(template) == nil
    assert Node.doctype_name(template) == nil
  end

  test "text: text accessors are populated and other accessors are nil" do
    output = parse!("<p>hello &amp; goodbye</p>")
    text = descendants(output) |> Enum.find(&(Node.type(&1) == :text))

    assert Node.type(text) == :text
    assert Node.text(text) == "hello & goodbye"
    assert Node.original_text(text) == "hello &amp; goodbye"
    assert %Gumbo.Position{} = Node.position(text)

    assert Node.tag(text) == nil
    assert Node.tag_name(text) == nil
    assert Node.namespace(text) == nil
    assert Node.original_tag(text) == nil
    assert Node.original_end_tag(text) == nil
    assert Node.end_position(text) == nil
    assert Node.has_doctype?(text) == nil
    assert Node.doctype_name(text) == nil
    assert Node.quirks_mode(text) == nil
  end

  test "comment: text is the comment body, original_text includes the delimiters" do
    output = parse!("<div><!-- a comment --></div>")
    comment = descendants(output) |> Enum.find(&(Node.type(&1) == :comment))

    assert Node.text(comment) == " a comment "
    assert Node.original_text(comment) == "<!-- a comment -->"
    assert Node.tag(comment) == nil
    assert Node.namespace(comment) == nil
  end

  test "cdata: text is the raw content, original_text includes the delimiters" do
    output = parse!("<svg><![CDATA[raw <text>]]></svg>")
    cdata = descendants(output) |> Enum.find(&(Node.type(&1) == :cdata))

    assert Node.text(cdata) == "raw <text>"
    assert Node.original_text(cdata) == "<![CDATA[raw <text>]]>"
    assert Node.tag(cdata) == nil
  end

  test "whitespace: text accessors are populated" do
    output = parse!("<div> <span>x</span> </div>")
    whitespace = descendants(output) |> Enum.find(&(Node.type(&1) == :whitespace))

    assert Node.text(whitespace) == " "
    assert Node.original_text(whitespace) == " "
    assert Node.tag(whitespace) == nil
  end

  test "processing instruction: text accessors are populated" do
    # "xml" and "xml-stylesheet" targets are bogus comments per the HTML
    # spec, so a non-reserved target is needed for a real PI node.
    output = parse!(~s(<?php echo "hi"; ?><html></html>))

    pi =
      Enum.find(
        Node.descendants(Output.document(output)),
        &(Node.type(&1) == :processing_instruction)
      )

    assert Node.text(pi) == "php echo \"hi\"; "
    assert Node.original_text(pi) == ~s(<?php echo "hi"; ?>)
    assert Node.tag(pi) == nil
  end

  test "details/1 returns the same values the individual accessors return" do
    output = parse!(~s(<!DOCTYPE html><div class="x">hi</div>))
    document = Output.document(output)
    div = descendants(output) |> Enum.find(&(Node.tag(&1) == :div))
    text = Enum.find(Node.children(div), &(Node.type(&1) == :text))

    assert {:ok, doc_details} = Node.details(document)
    assert Enum.sort(Map.keys(doc_details)) == Enum.sort(@details_keys)
    assert doc_details.type == Node.type(document)
    assert doc_details.has_doctype == Node.has_doctype?(document)
    assert doc_details.doctype_name == Node.doctype_name(document)
    assert doc_details.public_identifier == Node.public_identifier(document)
    assert doc_details.system_identifier == Node.system_identifier(document)
    assert doc_details.quirks_mode == Node.quirks_mode(document)
    assert doc_details.tag == nil
    assert doc_details.text == nil

    assert {:ok, div_details} = Node.details(div)
    assert div_details.type == Node.type(div)
    assert div_details.index_within_parent == Node.index_within_parent(div)
    assert div_details.parse_flags == Node.parse_flags(div)
    assert div_details.position == Node.position(div)
    assert div_details.tag == Node.tag(div)
    assert div_details.tag_name == Node.tag_name(div)
    assert div_details.namespace == Node.namespace(div)
    assert div_details.original_tag == Node.original_tag(div)
    assert div_details.original_end_tag == Node.original_end_tag(div)
    assert div_details.end_position == Node.end_position(div)
    assert div_details.text == nil
    assert div_details.original_text == nil
    assert div_details.has_doctype == nil
    assert div_details.doctype_name == nil

    assert {:ok, text_details} = Node.details(text)
    assert text_details.text == Node.text(text)
    assert text_details.original_text == Node.original_text(text)
    assert text_details.tag == nil
    assert text_details.namespace == nil
  end

  test "position/1 of the document node is the empty position" do
    output = parse!("<p>x</p>")

    assert Node.position(Output.document(output)) == %Gumbo.Position{
             line: 0,
             column: 0,
             offset: 0
           }
  end
end
