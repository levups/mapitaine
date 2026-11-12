# frozen_string_literal: true

module Mapitaine
  # Writes the pages of one shard as gzipped sitemap files, opening a second file when the first is full.
  class ShardWriter
    # https://www.sitemaps.org/protocol.html: 50,000 URLs and 50MB (52,428,800 bytes) a file, uncompressed.
    MAX_URLS_PER_FILE = 50_000
    MAX_BYTES_PER_FILE = 52_428_800

    Written = Data.define(:name, :path, :url_count, :lastmod, :digest)

    attr_reader :files

    def initialize(directory:, basename:, max_urls: MAX_URLS_PER_FILE, max_bytes: MAX_BYTES_PER_FILE)
      @directory = directory
      @basename = basename
      @max_urls = max_urls
      @max_bytes = max_bytes
      @files = []
    end

    # The entries of one page stay in the same file.
    def add(entries, lastmod)
      bytes = entries.sum(&:bytesize)
      roll if @gzip && (@url_count + entries.size > @max_urls || @bytes + bytes > @max_bytes)
      open_file unless @gzip
      entries.each { |entry| write(entry) }
      @url_count += entries.size
      @lastmod = [@lastmod, lastmod].compact.max
    end

    def close
      roll if @gzip
      self
    end

    def content_digest
      Digest::SHA256.hexdigest(@files.map(&:digest).join)
    end

    private

    def open_file
      suffix = @files.empty? ? "" : "-#{@files.size + 1}"
      @name = "#{@basename}#{suffix}.xml.gz"
      @path = File.join(@directory, @name)
      @gzip = Zlib::GzipWriter.open(@path)
      @file_digest = Digest::SHA256.new
      @url_count = 0
      @bytes = Xml::URLSET_CLOSE.bytesize
      @lastmod = nil
      write(Xml::URLSET_OPEN)
    end

    def roll
      write(Xml::URLSET_CLOSE)
      @gzip.close
      @gzip = nil
      @files << Written.new(name: @name, path: @path, url_count: @url_count, lastmod: @lastmod, digest: @file_digest.hexdigest)
    end

    def write(text)
      @gzip.write(text)
      @file_digest << text
      @bytes += text.bytesize
    end
  end
end
