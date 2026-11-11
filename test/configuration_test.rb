# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < MapitaineTest
  def test_the_host_loses_its_trailing_slash_and_must_be_a_url
    Mapitaine.configuration.host = "https://example.com/"

    assert_equal "https://example.com", Mapitaine.configuration.host
    ["example.com", "ftp://example.com", "https://", nil, "not a url"].each do |host|
      assert_raises(Mapitaine::ConfigurationError, host.inspect) { Mapitaine.configuration.host = host }
    end
  end

  def test_a_build_without_a_host_says_so
    Mapitaine.reset_configuration
    Mapitaine.configuration.storage = storage

    assert_equal "Mapitaine.configuration.host is not set", assert_raises(Mapitaine::ConfigurationError) { Mapitaine.build }.message
  end

  def test_locales_default_to_the_languages_of_the_app
    Mapitaine.reset_configuration

    assert_equal I18n.available_locales, Mapitaine.configuration.locales
  end

  def test_sources_default_to_every_class_with_a_scope_once_loaded
    loaded = false
    Mapitaine.configuration.sources = nil
    Mapitaine.configuration.load_sources = -> { loaded = true }
    sources = Mapitaine.configuration.sources

    assert loaded
    assert_includes sources, PostSitemap
    refute_includes sources, Mapitaine::Source
    assert_equal sources.map(&:slug).sort, sources.map(&:slug)
  end

  def test_the_filename_names_every_file
    Mapitaine.configuration.filename = "map"
    create_post(1)
    build

    assert_equal %w[map-manifest.json map-page.xml.gz map-post-00000.xml.gz map.xml], storage.content_by_name.keys.sort
  end
end
