# frozen_string_literal: true

module Mapitaine
  class Builder
    Result = Data.define(:written, :kept, :deleted, :url_count, :submitted, :warnings) do
      def changed?
        written.any? || deleted.any?
      end
    end

    Warning = Data.define(:source, :url, :message) do
      def to_s
        "#{source}: #{url} #{message}"
      end
    end

    def initialize(configuration, storage: configuration.storage, submit: true)
      @configuration = configuration
      @storage = storage
      @submit = submit
    end

    def build(full: false)
      ActiveSupport::Notifications.instrument("build.mapitaine", full:) do |payload|
        payload[:result] = Dir.mktmpdir("mapitaine") { |directory| build_in(directory, full:) }
      end
    end

    private

    def build_in(directory, full:)
      @directory = directory
      @previous = Manifest.read(@storage, manifest_name)
      @reusable = !full && @previous.digest == @configuration.digest
      @manifest = Manifest.new(digest: @configuration.digest, built_at: Time.now)
      @written = []
      @kept = []
      @warnings = []
      @changed_urls = []

      @configuration.sources.each { |source_class| build_source(source_class.new(@configuration)) }
      publish_index
      deleted = @previous.file_names - @manifest.file_names
      deleted.each { |name| @storage.delete(name) }
      upload(manifest_name, @manifest.to_json)

      Result.new(written: @written, kept: @kept, deleted:, url_count: @manifest.files.sum { |file| file["urls"] },
        submitted: submit_changed_urls, warnings: @warnings)
    end

    def build_source(source)
      seen_urls = Set.new
      source.fingerprint_by_shard.sort_by { |shard, _fingerprint| shard.to_i }.each do |shard, fingerprint|
        stored = @previous.shard(source.slug, shard) if @reusable
        if fingerprint && stored && stored["fingerprint"] == fingerprint
          keep(source, shard, stored)
        else
          render(source, shard, fingerprint, stored, seen_urls)
        end
      end
    end

    def keep(source, shard, stored)
      @manifest.record(source.slug, shard, fingerprint: stored["fingerprint"], files: stored["files"])
      @kept.concat(stored["files"].map { |file| file["name"] })
    end

    def render(source, shard, fingerprint, stored, seen_urls)
      writer = ShardWriter.new(directory: @directory, basename: source.basename(shard))
      changed_urls = []
      ActiveSupport::Notifications.instrument("shard.mapitaine", source: source.slug, shard:) do
        source.each_page(shard) do |page|
          inspect_page(source, page, seen_urls)
          writer.add(Xml.url_entries(page, x_default: @configuration.x_default), Xml.timestamp(page.lastmod))
          changed_urls.concat(page.urls) if changed_since_last_build?(page)
        end
        writer.close
      end

      fingerprint ||= writer.content_digest
      return keep(source, shard, stored) if stored && stored["fingerprint"] == fingerprint

      publish(source, shard, fingerprint, writer.files)
      @changed_urls.concat(changed_urls)
    end

    def publish(source, shard, fingerprint, files)
      files.each do |file|
        @storage.write(file.name, file.path)
        File.delete(file.path)
      end
      @written.concat(files.map(&:name))
      @manifest.record(source.slug, shard, fingerprint:, files: files.map do |file|
        {"name" => file.name, "urls" => file.url_count, "lastmod" => file.lastmod}
      end)
    end

    def publish_index
      entries = @manifest.files.map do |file|
        Xml.sitemap_entry("#{@configuration.sitemaps_url}/#{file["name"]}", file["lastmod"])
      end
      upload("#{@configuration.filename}.xml", "#{Xml::INDEX_OPEN}#{entries.join}#{Xml::INDEX_CLOSE}")
    end

    def upload(name, content)
      path = File.join(@directory, name)
      File.write(path, content)
      @storage.write(name, path)
    end

    def manifest_name
      "#{@configuration.filename}-manifest.json"
    end

    def inspect_page(source, page, seen_urls)
      page.urls.each do |url|
        warn(source, url, "is outside #{@configuration.host!}") unless url.start_with?("#{@configuration.host!}/") || url == @configuration.host!
        warn(source, url, "is listed twice") unless seen_urls.add?(url)
      end
      modified_at = page.modified_at
      warn(source, page.urls.first, "has a lastmod in the future (#{Xml.timestamp(page.lastmod)})") if modified_at && modified_at > @manifest.built_at
    end

    def warn(source, url, message)
      @warnings << Warning.new(source: source.slug, url:, message:)
    end

    # The first build has no "before": submitting a whole site at once is not what IndexNow is for.
    def changed_since_last_build?(page)
      modified_at = page.modified_at
      @previous.built_at && modified_at && modified_at >= @previous.built_at
    end

    def submit_changed_urls
      key = @configuration.index_now_key
      return 0 unless @submit && key

      upload("#{key}.txt", key) unless @configuration.index_now_key_location
      return 0 if @changed_urls.empty?

      IndexNow.new(host: @configuration.host!, key:, key_location: @configuration.index_now_key_location).submit(@changed_urls)
    rescue *IndexNow::NETWORK_ERRORS => exception
      # The sitemaps are published: a search engine that cannot be reached must not fail the build.
      @warnings << Warning.new(source: "indexnow", url: IndexNow::ENDPOINT.to_s, message: "could not be reached (#{exception.class})")
      0
    end
  end
end
