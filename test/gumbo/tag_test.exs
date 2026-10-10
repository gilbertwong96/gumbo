defmodule Gumbo.TagTest do
  use ExUnit.Case, async: true

  test "name/1 returns gumbo's normalized name" do
    assert Gumbo.Tag.name(:div) == "div"
    assert Gumbo.Tag.name(:h1) == "h1"
    assert Gumbo.Tag.name(:"annotation-xml") == "annotation-xml"
  end

  test ":unknown is faithful to gumbo, which returns an empty string" do
    assert Gumbo.Tag.name(:unknown) == ""
  end

  test "from_name/1 is length-aware and case-insensitive" do
    assert Gumbo.Tag.from_name("div") == :div
    assert Gumbo.Tag.from_name("DIV") == :div
    assert Gumbo.Tag.from_name("my-custom-tag") == :unknown
    assert Gumbo.Tag.from_name("") == :unknown
  end

  test "every tag except :unknown round-trips through name/1 and from_name/1" do
    for tag <- Gumbo.Tag.all(), tag != :unknown do
      assert Gumbo.Tag.from_name(Gumbo.Tag.name(tag)) == tag
    end
  end

  test "all/0 has no duplicate names, so no tag silently collapsed to :unknown" do
    names = Enum.map(Gumbo.Tag.all(), &Gumbo.Tag.name/1)
    # 154 real names in gumbo's tag_strings.h, plus GUMBO_TAG_UNKNOWN. The
    # literal is deliberate: a gumbo bump that adds a tag should make someone
    # look here rather than pass silently.
    assert length(names) == 155
    assert length(Enum.uniq(names)) == length(names)
    assert :unknown in Gumbo.Tag.all()
  end

  test "void?/1 matches the HTML void element list" do
    for tag <- [
          :area,
          :base,
          :br,
          :col,
          :embed,
          :hr,
          :img,
          :input,
          :link,
          :meta,
          :source,
          :track,
          :wbr,
          :basefont,
          :bgsound,
          :frame,
          :keygen,
          :param
        ] do
      assert Gumbo.Tag.void?(tag), "expected #{tag} to be void"
    end

    assert Gumbo.Tag.void?(:div) == false
    assert Gumbo.Tag.void?(:script) == false
  end

  test "void?/1 is total over every tag" do
    for tag <- Gumbo.Tag.all(), do: assert(is_boolean(Gumbo.Tag.void?(tag)))
  end

  test "name/1 rejects an out-of-range integer instead of aborting on gumbo's assert" do
    assert Gumbo.Tag.name(999_999) == nil
    assert Gumbo.Tag.name(-1) == nil
  end

  test "name/1 and all/0 are stable across 100_000 calls with garbage collection" do
    # A use-after-free in name/1's cached binaries would not show up on a
    # single call; the loop plus periodic GC is what exposes it.
    tags = Gumbo.Tag.all()
    names = Enum.map(tags, &Gumbo.Tag.name/1)
    assert length(names) == 155

    for i <- 1..100_000 do
      idx = rem(i, 155)
      assert Gumbo.Tag.name(Enum.at(tags, idx)) == Enum.at(names, idx)

      if rem(i, 10_000) == 0 do
        :erlang.garbage_collect()
        assert Gumbo.Tag.all() == tags
      end
    end
  end

  test "svg_name/1 case-corrects the SVG replacements and returns nil otherwise" do
    assert Gumbo.Tag.svg_name("clippath") == "clipPath"
    assert Gumbo.Tag.svg_name("foreignobject") == "foreignObject"
    assert Gumbo.Tag.svg_name("CLIPPATH") == "clipPath"
    assert Gumbo.Tag.svg_name("div") == nil
  end

  test "from_original_text/1 extracts the name from a start or end tag" do
    # Verified against the pinned parser: original_tag and original_end_tag in a
    # real tree are ALWAYS complete tags including the trailing '>'. Gumbo
    # documents the input as "<tagname>" or "</tagname>" and asserts on all four
    # shape conditions, so a piece without the closing '>' is an invalid input
    # that would trip a live assert — not a case to tolerate.
    assert Gumbo.Tag.from_original_text("<div class=\"x\">") == {:ok, "div"}
    assert Gumbo.Tag.from_original_text("</div>") == {:ok, "div"}
    assert Gumbo.Tag.from_original_text("<my-tag data-a=1>") == {:ok, "my-tag"}
    assert Gumbo.Tag.from_original_text("<div>") == {:ok, "div"}
    assert Gumbo.Tag.from_original_text("<br>") == {:ok, "br"}
  end

  test "from_original_text/1 refuses anything that would trip gumbo's asserts" do
    # The first five violate one of gumbo's four shape preconditions. "<>" and
    # "</>" satisfy all four but yield an empty name, so that check is ours.
    for bad <- ["", "<", "<a", "abc", "</", "<>", "</>", "div>", "a<b>"] do
      assert Gumbo.Tag.from_original_text(bad) == {:error, :not_a_tag}
    end
  end
end
