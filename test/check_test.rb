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
    wrong = Class.new(PostSitemap) { url { |post, locale| (post.id == 1) ? "https://example.org/#{locale}" : "/same" } }
    Mapitaine.configuration.sources = [wrong]

    assert_equal [
      "post: https://example.org/en is outside https://example.com",
      "post: https://example.org/fr is outside https://example.com",
      "post: https://example.org/en has a lastmod in the future (2999-01-01T00:00:00Z)",
      "post: https://example.com/same is listed twice"
    ], Mapitaine.check.map(&:to_s)
  end

  def test_a_build_reports_what_it_renders
    create_post(1, updated_at: Time.utc(2999, 1, 1))

    assert_equal 1, build.warnings.size
    assert_empty build.warnings
  end
end
