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
      requests << [uri.to_s, JSON.parse(body), headers]
      raise test.network_error if test.network_error

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

  def test_a_key_the_site_already_serves_is_named_and_not_published
    Mapitaine.configuration.index_now_key_location = "/indexnow-key.txt"
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    build

    refute storage.content_by_name.key?("0123456789abcdef.txt")
    assert_equal "https://example.com/indexnow-key.txt", @requests.dig(0, 1, "keyLocation")
  end

  def test_a_refusal_is_reported_and_sent_again_with_the_next_build
    create_post(1)
    create_post(2)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    self.response_code = "429"
    refused = build

    assert_equal 0, refused.submitted
    assert_equal ["indexnow: https://api.indexnow.org/indexnow answered 429 for 2 URLs of https://example.com, sent again with the next build"],
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

  def test_a_new_configuration_or_new_ranges_send_only_what_changed
    create_post(5)
    create_post(15)
    build
    Mapitaine.configuration.locales = %i[en fr de]

    assert_equal 0, build.submitted
    Mapitaine.configuration.sources = [Class.new(PostSitemap) { shard_size 20 }, PageSitemap]
    Post.find(5).update!(title: "Edited", updated_at: Time.now)

    build

    assert_equal %w[https://example.com/en/posts/5 https://example.com/fr/posts/5], @requests.last.dig(1, "urlList")
  end

  def test_a_build_that_dies_while_submitting_leaves_its_urls_for_the_next
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    self.network_error = RuntimeError

    assert_raises(RuntimeError) { build }
    self.network_error = nil

    assert_equal 2, build.submitted
  end

  def test_a_year_alone_is_not_a_change
    create_post(1)
    create_post(2)
    yearly = Class.new(PostSitemap) { lastmod { "2026" } }
    Mapitaine.configuration.sources = [yearly]
    build
    Post.where(id: 2).delete_all
    build

    assert_equal %w[https://example.com/en/posts/2 https://example.com/fr/posts/2], @requests.last.dig(1, "urlList")
  end

  def test_check_reports_a_key_the_site_does_not_serve
    Mapitaine.configuration.sitemaps_url = "https://cdn.example.com/sitemaps"

    assert_equal 1, Mapitaine.check.size
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

  def test_each_host_is_sent_its_own_urls_and_where_it_serves_the_key
    Mapitaine.configuration.host_by_locale = {fr: "https://fr.example.com"}
    Mapitaine.configuration.index_now_key_location = "/indexnow-key.txt"
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    built = build

    assert_equal [
      {"host" => "example.com", "key" => "0123456789abcdef", "keyLocation" => "https://example.com/indexnow-key.txt",
       "urlList" => %w[https://example.com/en/posts/1]},
      {"host" => "fr.example.com", "key" => "0123456789abcdef", "keyLocation" => "https://fr.example.com/indexnow-key.txt",
       "urlList" => %w[https://fr.example.com/fr/posts/1]}
    ], @requests.map { |request| request[1] }
    assert_equal 2, built.submitted
    assert_empty built.warnings
  end

  def test_a_host_whose_name_begins_like_another_is_sent_its_own_urls
    Mapitaine.configuration.host_by_locale = {fr: "https://example.community"}
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    build

    assert_equal [["example.com", %w[https://example.com/en/posts/1]], ["example.community", %w[https://example.community/fr/posts/1]]],
      @requests.map { |request| request[1].values_at("host", "urlList") }
  end

  def test_a_key_the_site_does_not_serve_is_reported
    Mapitaine.configuration.sitemaps_url = "https://cdn.example.com/sitemaps"
    create_post(1)
    built = build

    refute storage.content_by_name.key?("0123456789abcdef.txt")
    assert_equal ["indexnow: https://example.com/0123456789abcdef.txt must hold the key: sitemaps go to https://cdn.example.com/sitemaps, " \
      'so put 0123456789abcdef.txt in public/ and set index_now_key_location to "/0123456789abcdef.txt"'], built.warnings.map(&:to_s)
    Mapitaine.configuration.index_now_key_location = "/0123456789abcdef.txt"

    assert_empty build.warnings
  end

  def test_an_unreachable_endpoint_is_a_warning_and_the_sitemaps_are_published
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    self.network_error = Errno::ECONNREFUSED
    built = build

    assert_equal ["indexnow: https://api.indexnow.org/indexnow could not be reached (Errno::ECONNREFUSED) for 2 URLs of https://example.com, " \
      "sent again with the next build"], built.warnings.map(&:to_s)
    assert_equal %w[sitemap-post-00000.xml.gz], built.written
  end

  def test_an_endpoint_that_cannot_be_reached_is_tried_once_however_many_hosts_wait
    Mapitaine.configuration.host_by_locale = {fr: "https://fr.example.com"}
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    self.network_error = Errno::ETIMEDOUT
    built = build

    assert_equal 1, @requests.size
    assert_equal %w[https://example.com https://fr.example.com].map { |host|
      "indexnow: https://api.indexnow.org/indexnow could not be reached (Errno::ETIMEDOUT) for 1 URLs of #{host}, sent again with the next build"
    }, built.warnings.map(&:to_s)
    assert_equal %w[https://example.com/en/posts/1 https://fr.example.com/fr/posts/1],
      JSON.parse(storage.content_by_name["sitemap-manifest.json"])["unsubmitted"]
  end

  def test_a_refusal_does_not_keep_the_next_host_from_being_asked
    Mapitaine.configuration.host_by_locale = {fr: "https://fr.example.com"}
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    self.response_code = "429"
    build

    assert_equal %w[example.com fr.example.com], @requests.map { |request| request.dig(1, "host") }
  end

  def test_urls_go_in_batches_of_ten_thousand
    batches = []
    transport = lambda do |_uri, body, _headers|
      batches << JSON.parse(body)["urlList"].size
      Response.new(code: "202")
    end
    index_now = Mapitaine::IndexNow.new(key: "key", transport:)

    replies = index_now.submit("https://example.com", Array.new(10_001) { |number| "https://example.com/#{number}" })

    assert_equal [10_000, 1], batches
    assert_equal [10_000, 1], replies.map { |reply| reply.urls.size }
    assert replies.all?(&:accepted?)
  end

  def test_each_batch_gets_its_own_reply
    statuses = ["202", Errno::ECONNRESET]
    transport = lambda do |_uri, _body, _headers|
      status = statuses.shift
      raise status if status.is_a?(Class)

      Response.new(code: status)
    end
    replies = Mapitaine::IndexNow.new(key: "key", transport:)
      .submit("https://example.com", Array.new(10_001) { |number| "https://example.com/#{number}" })

    assert_equal [202, "Errno::ECONNRESET"], replies.map(&:status)
    assert_equal [true, false], replies.map(&:accepted?)
  end

  def test_a_reply_that_cannot_be_read_and_a_proxy_that_refuses_are_network_errors
    errors = [IOError.new("closed stream"), Net::HTTPBadResponse.new("wrong status line"), Net::HTTPHeaderSyntaxError.new("wrong Content-Length format"),
      Zlib::DataError.new("incorrect header check"), Net::HTTPFatalError.new("503", nil)]
    statuses = errors.map do |error|
      Mapitaine::IndexNow.new(key: "key", transport: ->(*) { raise error }).submit("https://example.com", %w[https://example.com/1]).first.status
    end

    assert_equal %w[IOError Net::HTTPBadResponse Net::HTTPHeaderSyntaxError Zlib::DataError Net::HTTPFatalError], statuses
  end

  def test_an_endpoint_that_cannot_be_reached_is_tried_once_however_many_batches_wait
    attempts = 0
    transport = lambda do |*|
      attempts += 1
      raise Errno::ETIMEDOUT
    end
    replies = Mapitaine::IndexNow.new(key: "key", transport:)
      .submit("https://example.com", Array.new(20_001) { |number| "https://example.com/#{number}" })

    assert_equal 1, attempts
    assert_equal ["Errno::ETIMEDOUT"] * 3, replies.map(&:status)
    assert_equal [10_000, 10_000, 1], replies.map { |reply| reply.urls.size }
  end

  def test_a_blank_key_is_no_key_even_while_urls_wait
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    self.response_code = "429"
    build
    Mapitaine.configuration.index_now_key = ""
    built = build

    refute storage.content_by_name.key?(".txt")
    assert_equal 1, @requests.size
    assert_equal 0, built.submitted
    assert_empty built.warnings
  end

  def test_check_submits_nothing
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    Mapitaine.check

    assert_empty @requests
  end
end
