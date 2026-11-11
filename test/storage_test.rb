# frozen_string_literal: true

require "test_helper"
require "active_storage"
require "active_storage/service/disk_service"
require "aws-sdk-s3"

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
      storage = Mapitaine::Storage::Local.new(public_directory)

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
      storage = Mapitaine::Storage::ActiveStorage.new(service, prefix: "sitemaps")

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
    with_file("") { |path| Mapitaine::Storage::ActiveStorage.new(service).write("sitemap-post-00000.xml.gz", path) }

    assert_equal [["sitemap-post-00000.xml.gz", {content_type: "application/gzip"}]], uploads
  end

  def test_s3_puts_under_the_prefix_with_a_content_type_and_the_options_given
    client = Aws::S3::Client.new(stub_responses: true)
    storage = Mapitaine::Storage::S3.new(bucket: "sitemaps", prefix: "example", client:, cache_control: "max-age=3600")
    with_file("<xml/>") do |path|
      storage.write("sitemap-post-00000.xml.gz", path)
      storage.write("sitemap.xml", path)
    end
    storage.delete("sitemap.xml")
    requests = client.api_requests.map { |request| [request[:operation_name], request[:params].slice(:bucket, :key, :content_type, :cache_control)] }

    assert_equal [
      [:put_object, {bucket: "sitemaps", key: "example/sitemap-post-00000.xml.gz", content_type: "application/gzip", cache_control: "max-age=3600"}],
      [:put_object, {bucket: "sitemaps", key: "example/sitemap.xml", content_type: "application/xml", cache_control: "max-age=3600"}],
      [:delete_object, {bucket: "sitemaps", key: "example/sitemap.xml"}]
    ], requests
  end

  def test_s3_reads_a_file_and_nil_when_there_is_none
    client = Aws::S3::Client.new(stub_responses: true)
    storage = Mapitaine::Storage::S3.new(bucket: "sitemaps", client:)
    client.stub_responses(:get_object, {body: "{}"}, "NoSuchKey")

    assert_equal "{}", storage.read("sitemap-manifest.json")
    assert_nil storage.read("sitemap-manifest.json")
  end
end
