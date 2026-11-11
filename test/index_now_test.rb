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

  def test_a_refusal_counts_no_url
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    self.response_code = "403"

    assert_equal 0, build.submitted
  end

  def test_an_unreachable_endpoint_is_a_warning_and_the_sitemaps_are_published
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    self.network_error = Errno::ECONNREFUSED
    built = build

    assert_equal ["indexnow: https://api.indexnow.org/indexnow could not be reached (Errno::ECONNREFUSED)"], built.warnings.map(&:to_s)
    assert_equal %w[sitemap-post-00000.xml.gz], built.written
  end

  def test_urls_go_in_batches_of_ten_thousand
    batches = []
    transport = lambda do |_uri, body, _headers|
      batches << JSON.parse(body)["urlList"].size
      Response.new(code: "202")
    end
    index_now = Mapitaine::IndexNow.new(host: "https://example.com", key: "key", transport:)

    assert_equal 10_001, index_now.submit(Array.new(10_001) { |number| "https://example.com/#{number}" })
    assert_equal [10_000, 1], batches
  end

  def test_check_submits_nothing
    create_post(1)
    build
    Post.find(1).update!(title: "Edited", updated_at: Time.now)
    Mapitaine.check

    assert_empty @requests
  end
end
