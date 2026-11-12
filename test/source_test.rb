# frozen_string_literal: true

require "test_helper"

class SourceTest < MaptainTest
  def test_the_slug_comes_from_the_class_name_or_is_given
    named = Class.new(PostSitemap) { slug "blog-posts" }

    assert_equal "post", PostSitemap.slug
    assert_equal "post", Class.new(PostSitemap).slug
    assert_equal "blog-posts", named.slug
    assert_equal "sitemap-blog-posts-00003", named.new(Maptain.configuration).basename("3")
  end

  def test_a_slug_that_would_leave_the_directory_is_refused
    error = assert_raises(Maptain::SourceError) { Class.new(PostSitemap) { slug "../etc" }.new(Maptain.configuration) }

    assert_includes error.message, %("../etc" must be lowercase letters)
  end

  def test_a_subclass_changes_its_own_definitions_only
    Class.new(PostSitemap) { shard_size 500 }

    assert_equal 10, PostSitemap.definitions[:shard_size]
  end

  def test_shards_hold_fewer_records_as_languages_multiply
    sizes = [%i[en], %i[en fr], Array.new(24) { |number| :"l#{number}" }].map do |locales|
      Maptain.configuration.locales = locales
      Class.new(PostSitemap) { definitions.delete(:shard_size) }.new(Maptain.configuration).send(:shard_size)
    end

    assert_equal [50_000, 25_000, 554], sizes
  end

  def test_a_model_without_an_integer_primary_key_is_refused
    Maptain.configuration.sources = [Class.new(PostSitemap) { scope { Token.all } }]

    assert_includes assert_raises(Maptain::SourceError) { build }.message, "integer primary key"
  end

  def test_a_record_without_a_url_in_a_language_is_left_out_of_it
    create_post(1)
    english_only = Class.new(PostSitemap) { url { |post, locale| post_url(post, locale:) if locale == :en } }
    pages = english_only.new(Maptain.configuration).each_page("0").to_a

    assert_equal [{"en" => "https://example.com/en/posts/1"}], pages.map(&:url_by_locale)
  end

  def test_route_helpers_use_the_configured_host_port_and_scheme
    Maptain.configuration.host = "http://localhost:3000/"
    create_post(1)

    assert_equal "http://localhost:3000/en/posts/1", first_page.urls.first
  end

  def test_route_helpers_and_paths_use_the_host_of_each_language
    Maptain.configuration.host_by_locale = {fr: "https://fr.example.com"}
    create_post(1)
    by_path = Class.new(PostSitemap) do
      url { |post, _locale| "/posts/#{post.id}" }
      images { |post| ["/images/#{post.id}.jpg", post_url(post, locale: :en)] }
    end
    page = first_page(by_path)

    assert_equal({"en" => "https://example.com/en/posts/1", "fr" => "https://fr.example.com/fr/posts/1"}, first_page.url_by_locale)
    assert_equal({"en" => "https://example.com/posts/1", "fr" => "https://fr.example.com/posts/1"}, page.url_by_locale)
    assert_equal %w[https://example.com/images/1.jpg https://example.com/en/posts/1], page.images
  end

  def test_the_url_block_runs_in_the_language_it_writes_when_i18n_has_it
    I18n.available_locales = %i[en fr]
    create_post(1, languages: "en,de,fr")
    translated = Class.new(PostSitemap) do
      url { |post, locale| post_url("#{post.id}-#{{en: "hello", fr: "bonjour"}.fetch(I18n.locale)}", locale:) }
    end
    failing = Class.new(PostSitemap) { url { |_post, locale| (locale == :en) ? raise("no URL") : "/#{locale}" } }

    I18n.with_locale(:fr) do
      assert_equal({"en" => "https://example.com/en/posts/1-hello", "de" => "https://example.com/de/posts/1-bonjour",
        "fr" => "https://example.com/fr/posts/1-bonjour"}, first_page(translated).url_by_locale)
      assert_equal :fr, I18n.locale
      assert_raises(RuntimeError) { first_page(failing) }
      assert_equal :fr, I18n.locale
    end
  ensure
    I18n.available_locales = nil
  end

  private

  def first_page(source_class = PostSitemap)
    source_class.new(Maptain.configuration).each_page("0").first
  end
end
