# frozen_string_literal: true

require "test_helper"

class ShardWriterTest < Minitest::Test
  def write(pages, **limits)
    Dir.mktmpdir do |directory|
      writer = Maptain::ShardWriter.new(directory:, basename: "sitemap-post-00000", **limits)
      pages.each { |entries, lastmod| writer.add(entries, lastmod) }
      yield writer.close.files, writer
    end
  end

  def entry(name)
    "<url><loc>https://example.com/#{name}</loc></url>\n"
  end

  def test_a_shard_over_the_url_limit_continues_in_a_second_file_and_pages_are_not_cut
    pages = [[[entry("a/en"), entry("a/fr")], "2026-01-01"], [[entry("b/en"), entry("b/fr")], "2026-01-03"],
      [[entry("c/en")], "2026-01-02"]]

    write(pages, max_urls: 3) do |files|
      assert_equal %w[sitemap-post-00000.xml.gz sitemap-post-00000-2.xml.gz], files.map(&:name)
      assert_equal [2, 3], files.map(&:url_count)
      assert_equal %w[2026-01-01 2026-01-03], files.map(&:lastmod)
      assert_equal "#{Maptain::Xml::URLSET_OPEN}#{entry("a/en")}#{entry("a/fr")}</urlset>\n", Zlib.gunzip(File.binread(files.first.path))
    end
  end

  def test_a_shard_over_the_byte_limit_continues_in_a_second_file
    envelope = Maptain::Xml::URLSET_OPEN.bytesize + Maptain::Xml::URLSET_CLOSE.bytesize
    pages = [[[entry("a")], nil], [[entry("b")], nil], [[entry("c")], nil]]

    write(pages, max_bytes: envelope + entry("a").bytesize * 2) do |files|
      assert_equal [2, 1], files.map(&:url_count)
      assert_equal [nil, nil], files.map(&:lastmod)
    end
  end

  def test_no_page_no_file
    write([]) { |files| assert_empty files }
  end

  def test_the_digest_follows_the_content
    digests = [["a"], ["a"], ["b"]].map { |names| write([[names.map { |name| entry(name) }, nil]]) { |_files, writer| writer.content_digest } }

    assert_equal digests[0], digests[1]
    refute_equal digests[0], digests[2]
  end
end
