# frozen_string_literal: true

require "test_helper"

class BuildTest < MapitaineTest
  def test_first_build_writes_a_file_per_shard_then_the_index_then_the_manifest
    create_post(1)
    create_post(12)
    built = build

    assert_equal %w[sitemap-post-00000.xml.gz sitemap-post-00001.xml.gz sitemap-page.xml.gz sitemap.xml sitemap-manifest.json],
      storage.writes
    assert_equal %w[sitemap-post-00000.xml.gz sitemap-post-00001.xml.gz sitemap-page.xml.gz], built.written
    assert_equal 6, built.url_count
    assert_empty built.warnings
  end

  def test_each_language_of_a_page_lists_all_of_them_and_the_default
    create_post(1)
    build

    assert_equal <<~XML, storage.xml("sitemap-post-00000.xml.gz")
      <?xml version="1.0" encoding="UTF-8"?>
      <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml" xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
      <url><loc>https://example.com/en/posts/1</loc><lastmod>2026-01-01T12:00:00Z</lastmod><xhtml:link rel="alternate" hreflang="en" href="https://example.com/en/posts/1"/><xhtml:link rel="alternate" hreflang="fr" href="https://example.com/fr/posts/1"/><xhtml:link rel="alternate" hreflang="x-default" href="https://example.com/en/posts/1"/></url>
      <url><loc>https://example.com/fr/posts/1</loc><lastmod>2026-01-01T12:00:00Z</lastmod><xhtml:link rel="alternate" hreflang="en" href="https://example.com/en/posts/1"/><xhtml:link rel="alternate" hreflang="fr" href="https://example.com/fr/posts/1"/><xhtml:link rel="alternate" hreflang="x-default" href="https://example.com/en/posts/1"/></url>
      </urlset>
    XML
  end

  def test_a_page_in_one_language_has_no_alternate_and_one_without_the_default_language_no_x_default
    create_post(1, languages: "fr")
    create_post(2, languages: "fr,de")
    build
    xml = storage.xml("sitemap-post-00000.xml.gz")

    assert_includes xml, "<url><loc>https://example.com/fr/posts/1</loc><lastmod>2026-01-01T12:00:00Z</lastmod></url>"
    assert_includes xml, %(hreflang="de" href="https://example.com/de/posts/2")
    refute_includes xml, "x-default"
  end

  def test_a_path_is_completed_with_the_host_and_a_date_stays_a_date
    build

    assert_includes storage.xml("sitemap-page.xml.gz"), "<url><loc>https://example.com/en/about</loc><lastmod>2026-01-15</lastmod>"
  end

  def test_the_index_lists_every_file_with_the_latest_change_it_holds
    create_post(1)
    create_post(2, updated_at: LONG_AGO + 3600)
    build

    assert_equal <<~XML, storage.xml("sitemap.xml")
      <?xml version="1.0" encoding="UTF-8"?>
      <sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <sitemap><loc>https://example.com/sitemap-post-00000.xml.gz</loc><lastmod>2026-01-01T13:00:00Z</lastmod></sitemap>
      <sitemap><loc>https://example.com/sitemap-page.xml.gz</loc><lastmod>2026-01-15</lastmod></sitemap>
      </sitemapindex>
    XML
  end

  def test_a_build_with_nothing_new_rewrites_no_sitemap_file
    create_post(1)
    create_post(12)
    build
    built = build

    assert_empty built.written
    assert_equal %w[sitemap-post-00000.xml.gz sitemap-post-00001.xml.gz sitemap-page.xml.gz], built.kept
    assert_equal %w[sitemap.xml sitemap-manifest.json], storage.writes
    refute_predicate built, :changed?
  end

  def test_an_updated_record_rewrites_its_shard_only
    create_post(1)
    create_post(12)
    build
    Post.find(12).update!(title: "Edited", updated_at: LONG_AGO + 60)
    built = build

    assert_equal %w[sitemap-post-00001.xml.gz], built.written
    assert_includes storage.xml("sitemap.xml"), "sitemap-post-00001.xml.gz</loc><lastmod>2026-01-01T12:01:00Z"
  end

  def test_update_all_and_deletions_are_seen_without_callbacks
    create_post(1)
    create_post(2)
    create_post(12)
    build
    Post.where(id: 12).update_all(updated_at: LONG_AGO + 60)
    Post.where(id: 2).delete_all
    built = build

    assert_equal %w[sitemap-post-00000.xml.gz sitemap-post-00001.xml.gz], built.written
    refute_includes storage.xml("sitemap-post-00000.xml.gz"), "posts/2"
  end

  def test_a_shard_left_without_records_loses_its_file
    create_post(1)
    create_post(12)
    build
    Post.find(12).update!(published: false)
    built = build

    assert_equal %w[sitemap-post-00001.xml.gz], built.deleted
    assert_equal %w[sitemap-post-00001.xml.gz], storage.deletions
    refute_includes storage.xml("sitemap.xml"), "sitemap-post-00001"
    assert_predicate built, :changed?
  end

  def test_a_full_build_rewrites_everything
    create_post(1)
    build
    built = build(full: true)

    assert_equal %w[sitemap-post-00000.xml.gz sitemap-page.xml.gz], built.written
  end

  def test_a_changed_configuration_rewrites_everything
    create_post(1)
    build
    Mapitaine.configuration.x_default = :fr
    built = build

    assert_equal %w[sitemap-post-00000.xml.gz sitemap-page.xml.gz], built.written
  end

  def test_an_unreadable_manifest_starts_over
    create_post(1)
    build
    storage.content_by_name["sitemap-manifest.json"] = "{"
    built = build

    assert_equal %w[sitemap-post-00000.xml.gz sitemap-page.xml.gz], built.written
  end

  def test_a_source_that_is_not_a_relation_is_rewritten_when_its_content_changes
    build
    Mapitaine.configuration.sources = [PostSitemap, Class.new(PageSitemap) { scope { %i[about about] } }]
    built = build

    assert_equal %w[sitemap-page.xml.gz], built.written
  end

  def test_the_scope_may_be_ordered
    create_post(1)
    ordered = Class.new(PostSitemap) { scope { Post.order(:title) } }
    Mapitaine.configuration.sources = [ordered]

    assert_equal %w[sitemap-post-00000.xml.gz], build.written
  end

  def test_sitemaps_served_from_elsewhere_are_listed_there
    create_post(1)
    Mapitaine.configuration.sitemaps_url = "https://cdn.example.com/sitemaps/"
    build

    assert_includes storage.xml("sitemap.xml"), "<loc>https://cdn.example.com/sitemaps/sitemap-post-00000.xml.gz</loc>"
  end

  def test_special_characters_are_escaped_and_images_listed
    create_post(1, title: %(Tom & "Jerry" <3))
    with_images = Class.new(PostSitemap) do
      url { |post, locale| "/#{locale}/posts?title=#{post.title}" }
      images { |post| ["/images/#{post.id}.jpg", "https://cdn.example.com/#{post.id}.jpg?a=1&b=2"] }
    end
    Mapitaine.configuration.sources = [with_images]
    build
    xml = storage.xml("sitemap-post-00000.xml.gz")

    assert_includes xml, "<loc>https://example.com/en/posts?title=Tom &amp; &quot;Jerry&quot; &lt;3</loc>"
    assert_includes xml, "<image:image><image:loc>https://example.com/images/1.jpg</image:loc></image:image>" \
                         "<image:image><image:loc>https://cdn.example.com/1.jpg?a=1&amp;b=2</image:loc></image:image></url>"
  end

  def test_a_lastmod_block_is_fingerprinted_by_the_expression_it_names
    create_post(1)
    reviewed = Class.new(PostSitemap) do
      lastmod { |post| [post.updated_at, post.reviewed_at].compact.max }
      fingerprint "COALESCE(posts.reviewed_at, posts.updated_at)"
    end
    Mapitaine.configuration.sources = [reviewed]
    build
    Post.where(id: 1).update_all(reviewed_at: LONG_AGO + 7200)
    built = build

    assert_equal %w[sitemap-post-00000.xml.gz], built.written
    assert_includes storage.xml("sitemap-post-00000.xml.gz"), "<lastmod>2026-01-01T14:00:00Z</lastmod>"
  end

  def test_a_build_is_instrumented
    create_post(1)
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(/mapitaine/) { |event| events << [event.name, event.payload] }
    built = build

    assert_equal ["shard.mapitaine", {source: "post", shard: "0"}], events.first
    assert_equal ["build.mapitaine", {full: false, result: built}], events.last
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
