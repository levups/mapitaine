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

  def test_a_language_may_have_a_host_of_its_own
    Mapitaine.configuration.host_by_locale = {:fr => "https://fr.example.com/", "fr-CA" => "https://fr.example.com", "pt-BR" => "https://br.example.com"}

    assert_equal "https://fr.example.com", Mapitaine.configuration.host_for(:fr)
    assert_equal "https://br.example.com", Mapitaine.configuration.host_for(:pt_BR)
    assert_equal "https://example.com", Mapitaine.configuration.host_for(:en)
    assert_equal %w[https://example.com https://fr.example.com https://br.example.com], Mapitaine.configuration.hosts
    assert_raises(Mapitaine::ConfigurationError) { Mapitaine.configuration.host_by_locale = {fr: "fr.example.com"} }
    assert_raises(FrozenError) { Mapitaine.configuration.host_by_locale[:de] = "de.example.com" }
  end

  def test_a_host_for_a_language_the_site_does_not_have_is_refused_when_a_build_starts
    Mapitaine.configuration.host_by_locale = {"FR" => "https://fr.example.com", :de => "https://de.example.com"}

    assert_equal 'host_by_locale["FR"] is not one of the locales: en, fr', assert_raises(Mapitaine::ConfigurationError) { build }.message
    assert_raises(Mapitaine::ConfigurationError) { Mapitaine.check }
    assert_empty storage.writes
    Mapitaine.configuration.locales = %i[en FR de]

    assert_empty build.warnings
  end

  def test_the_key_location_is_a_path_every_host_serves
    Mapitaine.configuration.index_now_key_location = "/indexnow-key.txt"

    assert_equal "/indexnow-key.txt", Mapitaine.configuration.index_now_key_location
    ["https://example.com/indexnow-key.txt", "//cdn.example.com/indexnow-key.txt", "indexnow-key.txt", "/", "/key.txt\nhttps://example.org"].each do |location|
      assert_raises(Mapitaine::ConfigurationError, location) { Mapitaine.configuration.index_now_key_location = location }
    end
  end

  def test_a_blank_key_and_a_blank_key_location_are_none
    Mapitaine.configuration.index_now_key = " "
    Mapitaine.configuration.index_now_key_location = ""

    assert_nil Mapitaine.configuration.index_now_key
    assert_nil Mapitaine.configuration.index_now_key_location
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
