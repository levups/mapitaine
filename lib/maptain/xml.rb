# frozen_string_literal: true

module Maptain
  module Xml
    DECLARATION = %(<?xml version="1.0" encoding="UTF-8"?>\n)
    URLSET_OPEN = %(#{DECLARATION}<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" ) +
      %(xmlns:xhtml="http://www.w3.org/1999/xhtml" ) +
      %(xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">\n)
    URLSET_CLOSE = "</urlset>\n"
    INDEX_OPEN = %(#{DECLARATION}<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n)
    INDEX_CLOSE = "</sitemapindex>\n"
    # Google reads no more than 1,000 images per URL.
    MAX_IMAGES_PER_URL = 1_000
    # https://www.w3.org/TR/NOTE-datetime: a year, a month, a day, or a time with its zone.
    W3C_DATE = /\A(\d{4})(?:-(\d{2})(?:-(\d{2}))?)?\z/
    W3C_TIME = /\A(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(Z|[+-]\d{2}:\d{2})\z/

    LOCATION = %r{<loc>([^<]*)</loc>}
    UNESCAPED_BY_ENTITY = {"&amp;" => "&", "&lt;" => "<", "&gt;" => ">", "&quot;" => '"', "&apos;" => "'"}.freeze

    module_function

    # One <url> per language. Each lists every language of the page, itself included: search engines drop
    # hreflang links that are not returned by the page they point to.
    def url_entries(page, x_default:)
      shared = "#{lastmod_tag(page.lastmod)}#{alternates(page, x_default)}#{images(page.images)}</url>\n"
      page.urls.map { |url| "<url><loc>#{escape(url)}</loc>#{shared}" }
    end

    def sitemap_entry(url, lastmod)
      "<sitemap><loc>#{escape(url)}</loc>#{lastmod_tag(lastmod)}</sitemap>\n"
    end

    # The W3C date or time of a lastmod, in UTC, or nil when it is not one.
    def timestamp(value)
      case value
      when nil then nil
      when DateTime then value.to_time.getutc.iso8601
      when Date then value.iso8601
      when String then w3c_timestamp(value)
      else value.getutc.iso8601 if value.respond_to?(:getutc)
      end
    end

    def w3c_timestamp(text)
      if (date = W3C_DATE.match(text))
        year, month, day = date.captures
        text if Date.valid_date?(year.to_i, (month || 1).to_i, (day || 1).to_i)
      elsif (time = W3C_TIME.match(text))
        year, month, day, hour, minute, second, zone = time.captures
        return unless Date.valid_date?(year.to_i, month.to_i, day.to_i)

        Time.new(year.to_i, month.to_i, day.to_i, hour.to_i, minute.to_i, second.to_i, (zone == "Z") ? "UTC" : zone).getutc.iso8601
      end
    rescue ArgumentError
      nil
    end

    # A date alone is the day as it starts first, at UTC+14: no time zone has it in the future after that.
    def time(stamp)
      return Time.iso8601(stamp) if stamp.include?("T")

      year, month, day = stamp.split("-").map(&:to_i)
      Time.new(year, month || 1, day || 1, 0, 0, 0, "+14:00")
    end

    # Rails locales spell regions with an underscore (pt_BR), hreflang with a hyphen (pt-BR).
    def hreflang(locale)
      locale.to_s.tr("_", "-")
    end

    # The <loc> of each <url> of a sitemap file.
    def locations(xml)
      xml.scan(LOCATION).map { |(location)| location.gsub(/&(?:amp|lt|gt|quot|apos);/, UNESCAPED_BY_ENTITY) }
    end

    def escape(text)
      text.to_s.encode(xml: :text).gsub('"', "&quot;")
    end

    def lastmod_tag(stamp)
      stamp ? "<lastmod>#{escape(stamp)}</lastmod>" : ""
    end

    def alternates(page, x_default)
      return "" if page.url_by_locale.size < 2

      links = page.url_by_locale.map { |locale, url| alternate(locale, url) }
      default_url = page.url_by_locale[x_default]
      links << alternate("x-default", default_url) if default_url
      links.join
    end

    def alternate(hreflang, url)
      %(<xhtml:link rel="alternate" hreflang="#{escape(hreflang)}" href="#{escape(url)}"/>)
    end

    def images(urls)
      urls.first(MAX_IMAGES_PER_URL).map { |url| "<image:image><image:loc>#{escape(url)}</image:loc></image:image>" }.join
    end
  end
end
