# frozen_string_literal: true

module Mapitaine
  class Builder
    # full: whether this build rewrote everything, asked to or because rebuild_every had passed.
    Result = Data.define(:full, :written, :kept, :deleted, :url_count, :submitted, :warnings) do
      def changed?
        written.any? || deleted.any?
      end
    end

    # https://www.sitemaps.org/protocol.html
    MAX_URL_CHARACTERS = 2_048
    MAX_FILES_PER_INDEX = 50_000
    LAST_TIME_ZONE_OFFSET_SECONDS = 12 * 60 * 60
    # One request's worth: what a refusing endpoint leaves in the manifest stays small.
    MAX_UNSUBMITTED_URLS = IndexNow::MAX_URLS_PER_REQUEST
    # A language, then maybe a script and a region: en, pt-BR, zh-Hant-TW, es-419.
    HREFLANG = /\A[a-z]{2,3}(-[a-z]{4})?(-([a-z]{2}|\d{3}))?\z/i

    # urls: every URL of the shard, kept only when IndexNow needs to know which ones appeared or went away.
    Rendered = Data.define(:source_slug, :shard, :fingerprint, :files, :changed_urls, :urls)

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
        payload[:full] = payload[:result].full
        payload[:result]
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
      # The first build has no "before": submitting a whole site at once is not what IndexNow is for.
      @tracking = @submit && @configuration.index_now_key.present? && @previous.built_at.present?

      @configuration.sources.each { |source_class| build_source(source_class.new(@configuration)) }
      publish_rendered
      publish_index
      deleted = (@previous.file_names | @previous.pending) - @manifest.file_names
      @changed_urls.concat(urls_in(deleted)) if @tracking
      deleted.each { |name| @storage.delete(name) }
      submitted = submit_changed_urls
      upload(manifest_name, @manifest.to_json)

      Result.new(full: @full, written: @written, kept: @kept, deleted:, url_count: @manifest.files.sum { |file| file["urls"] },
        submitted:, warnings: @warnings)
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
      urls = [] if @tracking
      ActiveSupport::Notifications.instrument("shard.mapitaine", source: source.slug, shard:) do
        source.each_page(shard) do |page|
          inspect_page(source, page, seen_urls)
          writer.add(Xml.url_entries(page, x_default: @x_default), page.lastmod)
          changed_urls.concat(page.urls) if @tracking && changed_since_last_build?(page)
          urls&.concat(page.urls)
        end
        writer.close
      end

      fingerprint ||= writer.content_digest
      # Recorded now, published once every shard is rendered: the index keeps the order of the sources.
      @manifest.record(source.slug, shard, fingerprint:, files: [])
      @rendered << Rendered.new(source_slug: source.slug, shard:, fingerprint:, files: writer.files, changed_urls:, urls:)
    end

    def publish_rendered
      changed_names = @rendered.flat_map(&:files).reject { |file| same_as_before?(file) }.to_set(&:name)
      announce_new_files(changed_names)
      @rendered.each do |rendered|
        changed = rendered.files.any? { |file| changed_names.include?(file.name) }
        note_changed_urls(rendered) if changed && @tracking
        entries = rendered.files.map do |file|
          changed = changed_names.include?(file.name)
          publish(file, changed)
          manifest_entry(file, changed)
        end
        @manifest.record(rendered.source_slug, rendered.shard, fingerprint: rendered.fingerprint, files: entries)
      end
    end

    # Read before the new files replace the old: a page that appeared or went away is a change too, whatever its
    # lastmod says.
    def note_changed_urls(rendered)
      previous_names = @previous.shard(rendered.source_slug, rendered.shard)&.fetch("files")&.map { |file| file["name"] } || []
      previous_urls = urls_in(previous_names).to_set
      urls = rendered.urls.to_set
      @changed_urls.concat(rendered.changed_urls, (urls - previous_urls).to_a, (previous_urls - urls).to_a)
    end

    def urls_in(names)
      names.flat_map do |name|
        content = @storage.read(name)
        content ? Xml.locations(Zlib.gunzip(content.b)) : []
      rescue Zlib::Error
        []
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
      elsif @previous_file_by_name.key?(file.name) && !later?(file.lastmod, previous_lastmod)
        @manifest.built_at.getutc.iso8601
      else
        file.lastmod
      end
      {"name" => file.name, "urls" => file.url_count, "lastmod" => lastmod, "digest" => file.digest}
    end

    # A manifest written by an older version may hold a lastmod in another format: compare times, not text.
    def later?(stamp, previous_stamp)
      return false if stamp.nil?

      previous_stamp = Xml.timestamp(previous_stamp)
      previous_stamp.nil? || Xml.time(stamp) > Xml.time(previous_stamp)
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
        warn(source, url, "is outside #{@configuration.host!}") unless on_host?(url)
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

    def on_host?(url)
      url.start_with?("#{@configuration.host!}/") || url == @configuration.host!
    end

    # A date alone may still be the day of the last build somewhere: it changed if it is not older than the date
    # at UTC-12, the last time zone to leave a day.
    def changed_since_last_build?(page)
      return false unless page.lastmod
      return page.modified_at >= @previous.built_at if page.lastmod.include?("T")

      last_date = (@previous.built_at - LAST_TIME_ZONE_OFFSET_SECONDS).utc.to_date.iso8601
      page.lastmod >= last_date[0, page.lastmod.length]
    end

    # Returns how many URLs the endpoint took. The ones it did not take, refused or unreachable, are kept in the
    # manifest and sent again with the next build: the sitemaps are published, so a refusal never fails the build.
    def submit_changed_urls
      key = @configuration.index_now_key
      return 0 unless @submit && key

      publish_index_now_key(key)
      urls = (@previous.unsubmitted + @changed_urls).uniq.select { |url| on_host?(url) }
      return 0 if urls.empty?

      replies = IndexNow.new(host: @configuration.host!, key:, key_location: @configuration.index_now_key_location).submit(urls)
      refused = replies.reject(&:accepted?)
      refused.group_by(&:status).each do |status, replies_with_status|
        count = replies_with_status.sum { |reply| reply.urls.size }
        answer = status.is_a?(Integer) ? "answered #{status}" : "could not be reached (#{status})"
        warn("indexnow", IndexNow::ENDPOINT, "#{answer} for #{count} URLs, sent again with the next build")
      end
      @manifest.unsubmitted.replace(refused.flat_map(&:urls).last(MAX_UNSUBMITTED_URLS))
      replies.select(&:accepted?).sum { |reply| reply.urls.size }
    end

    # IndexNow reads the key at the root of the site unless told where it is, and only on the site's host.
    def publish_index_now_key(key)
      location = @configuration.index_now_key_location
      if location
        warn("indexnow", location, "is not on #{@configuration.host!}: IndexNow only reads a key there") unless on_host?(location)
      elsif @configuration.sitemaps_url == @configuration.host!
        upload("#{key}.txt", key)
      else
        warn("indexnow", "#{@configuration.host!}/#{key}.txt", "must hold the key: sitemaps go to #{@configuration.sitemaps_url}, " \
          "so put #{key}.txt in public/ and set index_now_key_location to this URL")
      end
    end
  end
end
