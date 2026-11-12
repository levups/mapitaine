# frozen_string_literal: true

require "test_helper"

class CheckTest < MaptainTest
  def test_a_sound_site_has_nothing_to_report_and_nothing_is_written
    create_post(1)

    assert_empty Maptain.check
    assert_empty storage.content_by_name
  end

  def test_a_url_on_another_host_a_duplicate_and_a_future_lastmod_are_reported
    create_post(1, updated_at: Time.utc(2999, 1, 1))
    create_post(12)
    create_post(13, languages: "en")
    wrong = Class.new(PostSitemap) { url { |post, locale| (post.id == 1) ? "https://example.org/#{locale}" : "/same" } }
    Maptain.configuration.sources = [wrong]

    assert_equal [
      "post: https://example.org/en is outside https://example.com, and 1 more like it",
      "post: https://example.org/en has a lastmod in the future (2999-01-01T00:00:00Z)",
      "post: https://example.com/same is the URL of every language of its page: does the url block use the locale?",
      "post: https://example.com/same is listed twice"
    ], Maptain.check.map(&:to_s)
  end

  def test_a_url_on_the_host_of_its_language_is_sound_and_one_on_no_host_of_the_site_is_reported
    Maptain.configuration.host_by_locale = {fr: "https://fr.example.com"}
    create_post(1)
    create_post(2)
    elsewhere = Class.new(PostSitemap) { url { |post, locale| (post.id == 1) ? post_url(post, locale:) : "https://#{locale}.example.org/#{post.id}" } }
    Maptain.configuration.sources = [elsewhere]

    assert_equal ["post: https://en.example.org/2 is outside https://example.com and the hosts of its other languages, and 1 more like it"],
      Maptain.check.map(&:to_s)
  end

  def test_a_mistake_many_urls_of_a_source_share_is_reported_once_with_how_many_others
    [1, 2, 12].each { |id| create_post(id, updated_at: Time.utc(2999, 1, id)) }
    elsewhere = Class.new(PostSitemap) { url { |post, locale| "https://www.example.com/#{locale}/posts/#{post.id}" } }
    forgetful = Class.new(PostSitemap) do
      slug "forgetful"
      url { |_post, locale| "/#{locale}/posts" }
    end
    Maptain.configuration.sources = [elsewhere, forgetful]
    warnings = Maptain.check

    assert_equal [
      "post: https://www.example.com/en/posts/1 is outside https://example.com, and 5 more like it",
      "post: https://www.example.com/en/posts/1 has a lastmod in the future (2999-01-01T00:00:00Z), and 2 more like it",
      "forgetful: https://example.com/en/posts has a lastmod in the future (2999-01-01T00:00:00Z), and 2 more like it",
      "forgetful: https://example.com/en/posts is listed twice, and 3 more like it"
    ], warnings.map(&:to_s)
    assert_equal [5, 2, 2, 3], warnings.map(&:others)
    assert_equal "is listed twice", warnings.last.message
  end

  def test_a_long_url_a_wrong_hreflang_and_a_lastmod_that_is_not_a_date_are_reported
    create_post(1, title: "a" * 2_100)
    wrong = Class.new(PostSitemap) do
      url { |post, locale| "/#{locale}/#{post.title}" }
      locales { %i[en english] }
      lastmod { "yesterday" }
    end
    Maptain.configuration.sources = [wrong]

    assert_equal [
      "post: https://example.com/en/#{"a" * 2_100} is longer than 2048 characters, and 1 more like it",
      %(post: https://example.com/english/#{"a" * 2_100} has hreflang "english", not a language code),
      %(post: https://example.com/en/#{"a" * 2_100} has a lastmod that is not a W3C date ("yesterday"), left out)
    ], Maptain.check.map(&:to_s)
  end

  def test_mistakes_every_page_repeats_are_reported_once_and_impossible_dates_left_out
    create_post(1)
    create_post(2)
    careless = Class.new(PostSitemap) do
      url { |post| "/posts/#{post.id}" }
      lastmod { "2026-13-01" }
    end
    Maptain.configuration.sources = [careless]

    assert_equal [
      "post: https://example.com/posts/1 is the URL of every language of its page: does the url block use the locale?",
      %(post: https://example.com/posts/1 has a lastmod that is not a W3C date ("2026-13-01"), left out)
    ], Maptain.check.map(&:to_s)
  end

  def test_a_date_is_in_the_future_only_once_it_has_started_nowhere
    dated = ->(date) { Class.new(PageSitemap) { lastmod { date } } }
    first_date_on_earth = Time.now.getlocal("+14:00").to_date
    Maptain.configuration.sources = [dated.call(first_date_on_earth)]

    assert_empty Maptain.check
    Maptain.configuration.sources = [dated.call(first_date_on_earth + 1)]

    assert_equal 1, Maptain.check.size
  end

  def test_one_wrong_hreflang_is_reported_once
    create_post(1, languages: "en_GB,zz_top")
    create_post(2, languages: "en_GB,zz_top")
    Maptain.configuration.sources = [PostSitemap]

    assert_equal [%(post: https://example.com/zz_top/posts/1 has hreflang "zz-top", not a language code)], Maptain.check.map(&:to_s)
  end

  def test_a_build_reports_what_it_renders
    create_post(1, updated_at: Time.utc(2999, 1, 1))
    create_post(2, updated_at: Time.utc(2999, 1, 1))

    assert_equal [1], build.warnings.map(&:others)
    assert_empty build.warnings
  end
end
