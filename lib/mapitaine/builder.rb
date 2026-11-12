# frozen_string_literal: true

module Mapitaine
  class Builder
    Result = Data.define(:written, :kept, :deleted, :url_count, :submitted, :warnings) do
      def changed?
        written.any? || deleted.any?
      end
    end

    # https://www.sitemaps.org/protocol.html
    MAX_URL_CHARACTERS = 2_048
    MAX_FILES_PER_INDEX = 50_000
    # A language, then maybe a script and a region: en, pt-BR, zh-Hant-TW, es-419.
    HREFLANG = /\A[a-z]{2,3}(-[a-z]{4})?(-([a-z]{2}|\d{3}))?\z/i

    Rendered = Data.define(:source, :shard, :fingerprint, :files, :changed_urls)

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
      @previous_file_by_name = @previous.files.to_h { |file| [file["name"], file] }
      built_at = Time.now
      @full = full || rebuild_due?(built_at)
      @reusable = !@full && @previous.digest == @configuration.digest
      @manifest = Manifest.new(digest: @configuration.digest, built_at:, rebuilt_at: @full ? built_at : @previous.rebuilt_at)
      @written = []
      @kept = []
      @warnings = []
      @changed_urls = []
      @checked_hreflangs = Set.new
      @reported = Set.new
      @x_default = Xml.hreflang(@configuration.x_default)

      @rendered = []

      @configuration.sources.each { |source_class| build_source(source_class.new(@configuration)) }
      publish_rendered
      publish_index
      deleted = (@previous.file_names | @previous.pending) - @manifest.file_names
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
          render(source, shard, fingerprint, seen_urls)
        end
      end
    end

    def keep(source, shard, stored)
      @manifest.record(source.slug, shard, fingerprint: stored["fingerprint"], files: stored["files"])
      @kept.concat(stored["files"].map { |file| file["name"] })
    end

    def render(source, shard, fingerprint, seen_urls)
      writer = ShardWriter.new(directory: @directory, basename: source.basename(shard))
      changed_urls = []
      ActiveSupport::Notifications.instrument("shard.mapitaine", source: source.slug, shard:) do
        source.each_page(shard) do |page|
          inspect_page(source, page, seen_urls)
          writer.add(Xml.url_entries(page, x_default: @x_default), page.lastmod)
          changed_urls.concat(page.urls) if changed_since_last_build?(page)
        end
        writer.close
      end

      fingerprint ||= writer.content_digest
      # Recorded now, published once every shard is rendered: the index keeps the order of the sources.
      @manifest.record(source.slug, shard, fingerprint:, files: [])
      @rendered << Rendered.new(source: source.slug, shard:, fingerprint:, files: writer.files, changed_urls:)
    end

    def publish_rendered
      changed_names = @rendered.flat_map(&:files).reject { |file| same_as_before?(file) }.to_set(&:name)
      announce_new_files(changed_names)
      @rendered.each do |rendered|
        changed = rendered.files.select { |file| changed_names.include?(file.name) }
        rendered.files.each { |file| publish(file, changed.include?(file)) }
        @manifest.record(rendered.source, rendered.shard, fingerprint: rendered.fingerprint,
          files: rendered.files.map { |file| manifest_entry(file, changed.include?(file)) })
        @changed_urls.concat(rendered.changed_urls) if changed.any?
      end
    end

    def same_as_before?(file)
      @previous_file_by_name.dig(file.name, "digest") == file.digest
    end

    # Recorded before the first upload, so that a build dying midway leaves no file the next one cannot remove.
    def announce_new_files(names)
      new_names = names.to_a - @previous_file_by_name.keys - @previous.pending
      return if new_names.empty?

      @previous.pending.concat(new_names)
      upload(manifest_name, @previous.to_json)
    end

    # A full build uploads every file, so that it also repairs a storage that lost one.
    def publish(file, changed)
      if changed || @full
        @storage.write(file.name, file.path)
        @written << file.name
      else
        @kept << file.name
      end
      File.delete(file.path)
    end

    # The index tells crawlers which files to read again: a file that changed gets a later date even when the
    # change is a removal, and one that did not keeps its date.
    def manifest_entry(file, changed)
      previous_lastmod = @previous_file_by_name.dig(file.name, "lastmod")
      lastmod = if !changed
        previous_lastmod
      elsif @previous_file_by_name.key?(file.name) && (file.lastmod.nil? || (previous_lastmod && file.lastmod <= previous_lastmod))
        @manifest.built_at.getutc.iso8601
      else
        file.lastmod
      end
      {"name" => file.name, "urls" => file.url_count, "lastmod" => lastmod, "digest" => file.digest}
    end

    def rebuild_due?(now)
      every = @configuration.rebuild_every
      every.present? && (@previous.rebuilt_at.nil? || @previous.rebuilt_at + every <= now)
    end

    def publish_index
      name = "#{@configuration.filename}.xml"
      entries = @manifest.files.map do |file|
        Xml.sitemap_entry("#{@configuration.sitemaps_url}/#{file["name"]}", file["lastmod"])
      end
      inspect_index("#{@configuration.sitemaps_url}/#{name}", entries.size)
      upload(name, "#{Xml::INDEX_OPEN}#{entries.join}#{Xml::INDEX_CLOSE}")
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
        warn(source, url, "is longer than #{MAX_URL_CHARACTERS} characters") if url.length > MAX_URL_CHARACTERS
      end
      page.url_by_locale.each do |hreflang, url|
        warn(source, url, "has hreflang #{hreflang.inspect}, not a language code") if @checked_hreflangs.add?(hreflang) && !hreflang.match?(HREFLANG)
      end
      if page.url_by_locale.size > 1 && page.urls.one?
        warn_once(source, :one_url, page.urls.first, "is the URL of every language of its page: does the url block use the locale?")
      end
      inspect_lastmod(source, page)
    end

    def inspect_lastmod(source, page)
      if page.rejected_lastmod
        warn_once(source, :rejected_lastmod, page.urls.first, "has a lastmod that is not a W3C date (#{page.rejected_lastmod.inspect}), left out")
      elsif page.modified_at && page.modified_at > @manifest.built_at
        warn(source, page.urls.first, "has a lastmod in the future (#{page.lastmod})")
      end
    end

    def inspect_index(url, file_count)
      return if file_count <= MAX_FILES_PER_INDEX

      warn("index", url, "lists #{file_count} files, more than #{MAX_FILES_PER_INDEX}: raise shard_size")
    end

    # For a mistake every page of a source would repeat.
    def warn_once(source, kind, url, message)
      warn(source, url, message) if @reported.add?([source.slug, kind])
    end

    def warn(source, url, message)
      @warnings << Warning.new(source: source.is_a?(Source) ? source.slug : source, url:, message:)
    end

    # The first build has no "before": submitting a whole site at once is not what IndexNow is for.
    def changed_since_last_build?(page)
      @previous.built_at && page.modified_at && page.modified_at >= @previous.built_at
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
