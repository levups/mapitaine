# frozen_string_literal: true

module Maptain
  # One page of the site: the same content at one URL per language, keyed by hreflang. lastmod is a W3C date;
  # rejected_lastmod what a source gave that was not one.
  Page = Data.define(:url_by_locale, :lastmod, :modified_at, :images, :rejected_lastmod) do
    def urls
      url_by_locale.values.uniq
    end
  end
end
