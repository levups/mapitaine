# frozen_string_literal: true

require "test_helper"
require "active_storage"
require "active_storage/service/disk_service"

class StorageTest < Minitest::Test
  def with_file(content)
    Dir.mktmpdir do |directory|
      path = File.join(directory, "source")
      File.write(path, content)
      yield path, directory
    end
  end

  def test_local_writes_reads_and_deletes_and_leaves_no_partial_file
    with_file("<xml/>") do |path, directory|
      public_directory = File.join(directory, "public")
      storage = Maptain::Storage::Local.new(public_directory)

      assert_nil storage.read("sitemap.xml")
      storage.write("sitemap.xml", path)

      assert_equal "<xml/>", storage.read("sitemap.xml")
      assert_equal %w[sitemap.xml], Dir.children(public_directory)

      storage.delete("sitemap.xml")
      storage.delete("sitemap.xml")

      assert_empty Dir.children(public_directory)
    end
  end

  def test_active_storage_goes_through_the_service_under_the_prefix
    with_file("<xml/>") do |path, directory|
      service = ActiveStorage::Service::DiskService.new(root: File.join(directory, "storage"))
      storage = Maptain::Storage::ActiveStorage.new(service, prefix: "sitemaps")

      assert_nil storage.read("sitemap.xml")
      storage.write("sitemap.xml", path)

      assert_equal "<xml/>", storage.read("sitemap.xml")
      assert service.exist?("sitemaps/sitemap.xml")

      storage.delete("sitemap.xml")

      assert_nil storage.read("sitemap.xml")
    end
  end

  def test_active_storage_tells_the_service_the_content_type
    uploads = []
    service = Object.new
    service.define_singleton_method(:upload) { |key, _io, **options| uploads << [key, options] }
    with_file("") { |path| Maptain::Storage::ActiveStorage.new(service).write("sitemap-post-00000.xml.gz", path) }

    assert_equal [["sitemap-post-00000.xml.gz", {content_type: "application/gzip"}]], uploads
  end
end
