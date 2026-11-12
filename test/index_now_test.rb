# frozen_string_literal: true

require "test_helper"

class IndexNowTest < MapitaineTest
  Response = Data.define(:code)

  def setup
    super
    Mapitaine.configuration.index_now_key = "0123456789abcdef"
    @requests = requests = []
    @response_code = "200"
    test = self
    @original_post = Net::HTTP.method(:post)
    replace_post do |uri, body, headers|
      raise test.network_error if test.network_error

      requests << [uri.to_s, JSON.parse(body), headers]
      Response.new(code: test.response_code)
    end
  end

  def teardown
    replace_post(&@original_post)
  end

  def replace_post(&)
    silence_warnings { Net::HTTP.define_singleton_method(:post, &) }
  end

  attr_accessor :network_error, :response_code

  def test_the_first_build_publishes_the_key_and_submits_nothing
    create_post(1)
    built = build

    assert_equal "0123456789abcdef", storage.content_by_name["0123456789abcdef.txt"]
    assert_empty @requests
    assert_equal 0, built.submitted
  end

  def test_later_builds_submit_the_urls_changed_since_the_last_one
    create_post(1)
    create_post(2)
    build
    Post.find(2).update!(title: "Edited", updated_at: Time.now)
    built = build

    assert_equal [["https://api.indexnow.org/indexnow",
      {"host" => "example.com", "key" => "0123456789abcdef",
       "urlList" => %w[https://example.com/en/posts/2 https://example.com/fr/posts/2]},
      {"Content-Type" => "application/json; charset=utf-8"}]], @requests
    assert_equal 2, built.submitted
  end

  def test_a_key_hosted_elsewhere_is_named_and_not_published
    Mapitaine.configuration.index_now_key_location = "https://example.com/keys/indexnow.txt"
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    build

    refute storage.content_by_name.key?("0123456789abcdef.txt")
    assert_equal "https://example.com/keys/indexnow.txt", @requests.dig(0, 1, "keyLocation")
  end

  def test_a_refusal_is_reported_and_sent_again_with_the_next_build
    create_post(1)
    create_post(2)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    self.response_code = "429"
    refused = build

    assert_equal 0, refused.submitted
    assert_equal ["indexnow: https://api.indexnow.org/indexnow answered 429 for 2 URLs, sent again with the next build"],
      refused.warnings.map(&:to_s)
    Post.find(2).update!(title: "Edited", updated_at: Time.now)
    self.response_code = "202"

    assert_equal 4, build.submitted
    assert_equal %w[https://example.com/en/posts/1 https://example.com/fr/posts/1 https://example.com/en/posts/2
      https://example.com/fr/posts/2], @requests.last.dig(1, "urlList")
  end

  def test_pages_that_appear_or_go_away_are_submitted_whatever_their_lastmod
    create_post(1)
    create_post(2)
    create_post(12)
    build
    Post.find(2).update!(published: false, updated_at: LONG_AGO)
    Post.where(id: 12).delete_all
    create_post(3)

    assert_equal 6, build.submitted
    assert_equal %w[https://example.com/en/posts/3 https://example.com/fr/posts/3 https://example.com/en/posts/2
      https://example.com/fr/posts/2 https://example.com/en/posts/12 https://example.com/fr/posts/12], @requests.last.dig(1, "urlList")
  end

  def test_a_date_of_the_day_of_the_last_build_is_a_change
    create_post(1)
    dated = Class.new(PostSitemap) { lastmod { |post| post.reviewed_at&.to_date || Date.new(2026, 1, 1) } }
    Mapitaine.configuration.sources = [dated]
    build
    Post.find(1).update!(reviewed_at: Time.now)

    assert_equal 2, build.submitted
  end

  def test_only_urls_of_the_host_are_submitted
    Mapitaine.configuration.sources = [Class.new(PostSitemap) { url { |post, locale| (locale == :fr) ? "https://example.fr/posts/#{post.id}" : "/en/posts/#{post.id}" } }]
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    build

    assert_equal %w[https://example.com/en/posts/1], @requests.last.dig(1, "urlList")
  end

  def test_a_key_the_site_does_not_serve_is_reported
    Mapitaine.configuration.sitemaps_url = "https://cdn.example.com/sitemaps"
    create_post(1)
    built = build

    refute storage.content_by_name.key?("0123456789abcdef.txt")
    assert_equal ["indexnow: https://example.com/0123456789abcdef.txt must hold the key: sitemaps go to https://cdn.example.com/sitemaps, " \
      "so put 0123456789abcdef.txt in public/ and set index_now_key_location to this URL"], built.warnings.map(&:to_s)
    Mapitaine.configuration.index_now_key_location = "https://cdn.example.com/sitemaps/0123456789abcdef.txt"

    assert_equal ["indexnow: https://cdn.example.com/sitemaps/0123456789abcdef.txt is not on https://example.com: IndexNow only reads a key there"],
      build.warnings.map(&:to_s)
  end

  def test_an_unreachable_endpoint_is_a_warning_and_the_sitemaps_are_published
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    self.network_error = Errno::ECONNREFUSED
    built = build

    assert_equal ["indexnow: https://api.indexnow.org/indexnow could not be reached (Errno::ECONNREFUSED) for 2 URLs, sent again with the next build"],
      built.warnings.map(&:to_s)
    assert_equal %w[sitemap-post-00000.xml.gz], built.written
  end

  def test_urls_go_in_batches_of_ten_thousand
    batches = []
    transport = lambda do |_uri, body, _headers|
      batches << JSON.parse(body)["urlList"].size
      Response.new(code: "202")
    end
    index_now = Mapitaine::IndexNow.new(host: "https://example.com", key: "key", transport:)

    replies = index_now.submit(Array.new(10_001) { |number| "https://example.com/#{number}" })

    assert_equal [10_000, 1], batches
    assert_equal [10_000, 1], replies.map { |reply| reply.urls.size }
    assert replies.all?(&:accepted?)
  end

  def test_check_submits_nothing
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    Mapitaine.check

    assert_empty @requests
  end
end
