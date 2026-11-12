# frozen_string_literal: true

module Maptain
  class Configuration
    # A full build now and then catches what no fingerprint sees: update_columns, a change in another table,
    # a new url block, a file removed from the storage.
    DEFAULT_REBUILD_EVERY_SECONDS = 7 * 24 * 60 * 60

    attr_accessor :filename, :index_now_key, :load_sources, :rebuild_every, :storage, :x_default
    attr_reader :host, :host_by_locale, :index_now_key_location
    attr_writer :locales, :sitemaps_url, :sources

    def initialize
      @filename = "sitemap"
      @host_by_locale = {}.freeze
      @load_sources = -> {}
      @rebuild_every = DEFAULT_REBUILD_EVERY_SECONDS
      @storage = Storage::Local.new("public")
    end

    def host=(url)
      @host = absolute_url(url, "host")
    end

    def host!
      host || raise(ConfigurationError, "Maptain.configuration.host is not set")
    end

    # Frozen: a host added in place would be neither checked nor found.
    def host_by_locale=(host_by_locale)
      @host_by_locale = host_by_locale.to_h do |locale, url|
        [Xml.hreflang(locale), absolute_url(url, "host_by_locale[#{locale.inspect}]")]
      end.freeze
    end

    def host_for(locale)
      host_by_locale.fetch(Xml.hreflang(locale)) { host! }
    end

    def hosts
      [host!, *host_by_locale.values].uniq
    end

    # A path, not a URL: IndexNow only reads a key on the host of the URLs it is given, so each host serves it.
    def index_now_key_location=(path)
      unless path.nil? || path.to_s.match?(%r{\A/[^/\s]\S*\z})
        raise ConfigurationError, "index_now_key_location must be a path such as \"/key.txt\", got #{path.inspect}"
      end

      @index_now_key_location = path&.to_s
    end

    def locales
      Array(@locales || I18n.available_locales)
    end

    # Where the sitemap files are served from, when that is not the site itself (a bucket, a CDN).
    def sitemaps_url
      @sitemaps_url ? absolute_url(@sitemaps_url, "sitemaps_url") : host!
    end

    def sources
      return @sources if @sources

      load_sources.call
      Source.descendants.select(&:scope?).sort_by(&:slug)
    end

    # Whatever changes every file: a build under another digest starts over.
    def digest
      Digest::SHA256.hexdigest(JSON.generate([VERSION, host!, host_by_locale, sitemaps_url, locales, x_default, filename]))
    end

    private

    def absolute_url(url, setting)
      uri = URI.parse(url.to_s)
      raise ConfigurationError, "#{setting} must be an http(s) URL, got #{url.inspect}" unless uri.is_a?(URI::HTTP) && uri.host.present?

      url.to_s.delete_suffix("/")
    rescue URI::InvalidURIError
      raise ConfigurationError, "#{setting} must be an http(s) URL, got #{url.inspect}"
    end
  end
end
