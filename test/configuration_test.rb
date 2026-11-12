# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < MaptainTest
  def test_the_host_loses_its_trailing_slash_and_must_be_a_url
    Maptain.configuration.host = "https://example.com/"

    assert_equal "https://example.com", Maptain.configuration.host
    ["example.com", "ftp://example.com", "https://", nil, "not a url"].each do |host|
      assert_raises(Maptain::ConfigurationError, host.inspect) { Maptain.configuration.host = host }
    end
  end

  def test_a_language_may_have_a_host_of_its_own
    Maptain.configuration.host_by_locale = {:fr => "https://fr.example.com/", "fr-CA" => "https://fr.example.com", "pt-BR" => "https://br.example.com"}

    assert_equal "https://fr.example.com", Maptain.configuration.host_for(:fr)
    assert_equal "https://br.example.com", Maptain.configuration.host_for(:pt_BR)
    assert_equal "https://example.com", Maptain.configuration.host_for(:en)
    assert_equal %w[https://example.com https://fr.example.com https://br.example.com], Maptain.configuration.hosts
    assert_raises(Maptain::ConfigurationError) { Maptain.configuration.host_by_locale = {fr: "fr.example.com"} }
    assert_raises(FrozenError) { Maptain.configuration.host_by_locale[:de] = "de.example.com" }
  end

  def test_a_host_for_a_language_the_site_does_not_have_is_refused_when_a_build_starts
    Maptain.configuration.host_by_locale = {"FR" => "https://fr.example.com", :pt_BR => "https://br.example.com"}

    assert_equal 'host_by_locale["FR"] is not one of the locales: en, fr', assert_raises(Maptain::ConfigurationError) { build }.message
    assert_raises(Maptain::ConfigurationError) { Maptain.check }
    assert_empty storage.writes
    Maptain.configuration.locales = %i[en FR pt_BR]

    assert_empty build.warnings
  end

  def test_the_key_location_is_a_path_every_host_serves
    Maptain.configuration.index_now_key_location = "/indexnow-key.txt"

    assert_equal "/indexnow-key.txt", Maptain.configuration.index_now_key_location
    ["https://example.com/indexnow-key.txt", "//cdn.example.com/indexnow-key.txt", "indexnow-key.txt", "/", "/key.txt\nhttps://example.org"].each do |location|
      assert_raises(Maptain::ConfigurationError, location) { Maptain.configuration.index_now_key_location = location }
    end
  end

  def test_a_blank_key_and_a_blank_key_location_are_none
    Maptain.configuration.index_now_key = " "
    Maptain.configuration.index_now_key_location = ""

    assert_nil Maptain.configuration.index_now_key
    assert_nil Maptain.configuration.index_now_key_location
  end

  def test_a_build_without_a_host_says_so
    Maptain.reset_configuration
    Maptain.configuration.storage = storage

    assert_equal "Maptain.configuration.host is not set", assert_raises(Maptain::ConfigurationError) { Maptain.build }.message
  end

  def test_locales_default_to_the_languages_of_the_app
    Maptain.reset_configuration

    assert_equal I18n.available_locales, Maptain.configuration.locales
  end

  def test_sources_default_to_every_class_with_a_scope_once_loaded
    loaded = false
    Maptain.configuration.sources = nil
    Maptain.configuration.load_sources = -> { loaded = true }
    sources = Maptain.configuration.sources

    assert loaded
    assert_includes sources, PostSitemap
    refute_includes sources, Maptain::Source
    assert_equal sources.map(&:slug).sort, sources.map(&:slug)
  end

  def test_the_filename_names_every_file
    Maptain.configuration.filename = "map"
    create_post(1)
    build

    assert_equal %w[map-manifest.json map-page.xml.gz map-post-00000.xml.gz map.xml], storage.content_by_name.keys.sort
  end
end
