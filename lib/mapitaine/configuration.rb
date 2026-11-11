# frozen_string_literal: true

module Mapitaine
  class Configuration
    attr_accessor :filename, :index_now_key, :index_now_key_location, :load_sources, :storage, :x_default
    attr_reader :host
    attr_writer :locales, :sitemaps_url, :sources

    def initialize
      @filename = "sitemap"
      @load_sources = -> {}
      @storage = Storage::Local.new("public")
    end

    def host=(url)
      @host = absolute_url(url, "host")
    end

    def host!
      host || raise(ConfigurationError, "Mapitaine.configuration.host is not set")
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
      Digest::SHA256.hexdigest([VERSION, host!, sitemaps_url, locales, x_default, filename].to_json)
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
