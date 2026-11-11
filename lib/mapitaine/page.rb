# frozen_string_literal: true

module Mapitaine
  # One page of the site: the same content at one URL per language.
  Page = Data.define(:url_by_locale, :lastmod, :images) do
    def urls
      url_by_locale.values
    end

    def modified_at
      lastmod.to_time if lastmod.respond_to?(:to_time)
    end
  end
end
