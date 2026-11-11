# frozen_string_literal: true

module Mapitaine
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

    def timestamp(value)
      return if value.nil?
      return value.utc.iso8601 if value.respond_to?(:utc)

      value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
    end

    def escape(text)
      text.to_s.encode(xml: :text).gsub('"', "&quot;")
    end

    def lastmod_tag(value)
      stamp = timestamp(value)
      stamp ? "<lastmod>#{escape(stamp)}</lastmod>" : ""
    end

    def alternates(page, x_default)
      return "" if page.url_by_locale.size < 2

      links = page.url_by_locale.map { |locale, url| alternate(locale, url) }
      links << alternate("x-default", page.url_by_locale[x_default]) if page.url_by_locale.key?(x_default)
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
