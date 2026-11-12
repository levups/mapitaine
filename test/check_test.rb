# frozen_string_literal: true

require "test_helper"

class CheckTest < MapitaineTest
  def test_a_sound_site_has_nothing_to_report_and_nothing_is_written
    create_post(1)

    assert_empty Mapitaine.check
    assert_empty storage.content_by_name
  end

  def test_a_url_on_another_host_a_duplicate_and_a_future_lastmod_are_reported
    create_post(1, updated_at: Time.utc(2999, 1, 1))
    create_post(12)
    create_post(13, languages: "en")
    wrong = Class.new(PostSitemap) { url { |post, locale| (post.id == 1) ? "https://example.org/#{locale}" : "/same" } }
    Mapitaine.configuration.sources = [wrong]

    assert_equal [
      "post: https://example.org/en is outside https://example.com",
      "post: https://example.org/fr is outside https://example.com",
      "post: https://example.org/en has a lastmod in the future (2999-01-01T00:00:00Z)",
      "post: https://example.com/same is the URL of every language of its page: does the url block use the locale?",
      "post: https://example.com/same is listed twice"
    ], Mapitaine.check.map(&:to_s)
  end

  def test_a_long_url_a_wrong_hreflang_and_a_lastmod_that_is_not_a_date_are_reported
    create_post(1, title: "a" * 2_100)
    wrong = Class.new(PostSitemap) do
      url { |post, locale| "/#{locale}/#{post.title}" }
      locales { %i[en english] }
      lastmod { "yesterday" }
    end
    Mapitaine.configuration.sources = [wrong]

    assert_equal [
      "post: https://example.com/en/#{"a" * 2_100} is longer than 2048 characters",
      "post: https://example.com/english/#{"a" * 2_100} is longer than 2048 characters",
      %(post: https://example.com/english/#{"a" * 2_100} has hreflang "english", not a language code),
      %(post: https://example.com/en/#{"a" * 2_100} has a lastmod that is not a W3C date ("yesterday"), left out)
    ], Mapitaine.check.map(&:to_s)
  end

  def test_mistakes_every_page_repeats_are_reported_once_and_impossible_dates_left_out
    create_post(1)
    create_post(2)
    careless = Class.new(PostSitemap) do
      url { |post| "/posts/#{post.id}" }
      lastmod { "2026-13-01" }
    end
    Mapitaine.configuration.sources = [careless]

    assert_equal [
      "post: https://example.com/posts/1 is the URL of every language of its page: does the url block use the locale?",
      %(post: https://example.com/posts/1 has a lastmod that is not a W3C date ("2026-13-01"), left out)
    ], Mapitaine.check.map(&:to_s)
  end

  def test_a_date_is_in_the_future_only_once_it_has_started_nowhere
    dated = ->(date) { Class.new(PageSitemap) { lastmod { date } } }
    first_date_on_earth = Time.now.getlocal("+14:00").to_date
    Mapitaine.configuration.sources = [dated.call(first_date_on_earth)]

    assert_empty Mapitaine.check
    Mapitaine.configuration.sources = [dated.call(first_date_on_earth + 1)]

    assert_equal 1, Mapitaine.check.size
  end

  def test_one_wrong_hreflang_is_reported_once
    create_post(1, languages: "en_GB,zz_top")
    create_post(2, languages: "en_GB,zz_top")
    Mapitaine.configuration.sources = [PostSitemap]

    assert_equal [%(post: https://example.com/zz_top/posts/1 has hreflang "zz-top", not a language code)], Mapitaine.check.map(&:to_s)
  end

  def test_a_build_reports_what_it_renders
    create_post(1, updated_at: Time.utc(2999, 1, 1))

    assert_equal 1, build.warnings.size
    assert_empty build.warnings
  end
end
