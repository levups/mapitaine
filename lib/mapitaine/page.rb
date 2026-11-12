# frozen_string_literal: true

module Mapitaine
  # One page of the site: the same content at one URL per language, keyed by hreflang.
  Page = Data.define(:url_by_locale, :lastmod, :images) do
    # Two languages may share a URL; the file lists it once.
    def urls
      url_by_locale.values.uniq
    end

    def modified_at
      return lastmod.getutc if lastmod.respond_to?(:getutc) && !lastmod.is_a?(Date)

      stamp = Xml.timestamp(lastmod)
      return unless stamp

      stamp.include?("T") ? Time.iso8601(stamp) : Time.utc(*stamp.split("-").map(&:to_i))
    end
  end
end
