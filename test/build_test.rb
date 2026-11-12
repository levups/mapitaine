# frozen_string_literal: true

require "test_helper"

class BuildTest < MapitaineTest
  def test_first_build_announces_its_files_writes_one_per_shard_then_the_index_then_the_manifest
    create_post(1)
    create_post(12)
    built = build

    assert_equal %w[sitemap-manifest.json sitemap-post-00000.xml.gz sitemap-post-00001.xml.gz sitemap-page.xml.gz sitemap.xml
      sitemap-manifest.json], storage.writes
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

  def test_a_record_replaced_by_an_older_one_rewrites_its_shard
    create_post(1, updated_at: LONG_AGO + 60)
    create_post(2)
    build
    Post.where(id: 2).delete_all
    create_post(3)
    built = build

    assert_equal %w[sitemap-post-00000.xml.gz], built.written
    assert_includes storage.xml("sitemap-post-00000.xml.gz"), "posts/3"
  end

  def test_ids_too_large_for_a_sum_are_fingerprinted
    create_post(9_000_000_000_000_000_001)
    create_post(9_000_000_000_000_000_002)
    build
    Post.where(id: 9_000_000_000_000_000_002).delete_all
    create_post(9_000_000_000_000_000_003)

    assert_equal %w[sitemap-post-900000000000000000.xml.gz], build.written
  end

  def test_a_new_shard_size_rewrites_the_source
    create_post(5)
    create_post(15)
    build
    Post.where(id: 15).delete_all
    create_post(25)
    Mapitaine.configuration.sources = [Class.new(PostSitemap) { shard_size 20 }, PageSitemap]
    built = build

    assert_equal %w[sitemap-post-00001.xml.gz], built.written
    assert_includes built.kept, "sitemap-post-00000.xml.gz"
    refute_includes storage.xml("sitemap-post-00001.xml.gz"), "posts/15"
    assert_includes storage.xml("sitemap-post-00001.xml.gz"), "posts/25"
  end

  def test_a_file_that_changed_moves_forward_in_the_index_even_when_a_record_left_it
    create_post(1)
    create_post(2)
    build
    Post.where(id: 2).delete_all
    built = build

    assert_equal %w[sitemap-post-00000.xml.gz], built.written
    stamp = storage.xml("sitemap.xml")[%r{sitemap-post-00000.xml.gz</loc><lastmod>([^<]+)}, 1]

    assert_operator Time.iso8601(stamp), :>, LONG_AGO
  end

  def test_a_file_dated_by_an_older_manifest_is_compared_by_time
    create_post(1, updated_at: Time.utc(2026, 1, 15, 5))
    build
    manifest = JSON.parse(storage.content_by_name["sitemap-manifest.json"])
    manifest["sources"]["post"]["0"]["files"][0]["lastmod"] = "2026-01-15T10:00:00+09:00"
    storage.content_by_name["sitemap-manifest.json"] = JSON.generate(manifest)
    Post.where(id: 1).update_all(title: "Edited", updated_at: Time.utc(2026, 1, 15, 6))
    build

    assert_includes storage.xml("sitemap.xml"), "sitemap-post-00000.xml.gz</loc><lastmod>2026-01-15T06:00:00Z</lastmod>"
  end

  def test_a_shard_rendered_again_without_a_visible_change_is_not_uploaded
    create_post(1)
    fixed = Class.new(PostSitemap) { lastmod { Date.new(2026, 1, 1) } }
    Mapitaine.configuration.sources = [fixed]
    build
    Post.where(id: 1).update_all(updated_at: LONG_AGO + 60)
    built = build

    assert_empty built.written
    assert_equal %w[sitemap-post-00000.xml.gz], built.kept
    assert_includes storage.xml("sitemap.xml"), "sitemap-post-00000.xml.gz</loc><lastmod>2026-01-01</lastmod>"
  end

  def test_a_full_build_uploads_everything_and_keeps_the_dates_of_what_did_not_change
    create_post(1)
    build
    index = storage.xml("sitemap.xml")
    storage.delete("sitemap-post-00000.xml.gz")
    built = build(full: true)

    assert_equal %w[sitemap-post-00000.xml.gz sitemap-page.xml.gz], built.written
    assert_equal index, storage.xml("sitemap.xml")
  end

  def test_a_full_build_comes_every_week_by_itself
    create_post(1)
    build
    manifest = JSON.parse(storage.content_by_name["sitemap-manifest.json"])
    manifest["rebuilt_at"] = (Time.now - 8 * 86_400).utc.iso8601
    storage.content_by_name["sitemap-manifest.json"] = JSON.generate(manifest)

    built = build

    assert_predicate built, :full
    assert_equal %w[sitemap-post-00000.xml.gz sitemap-page.xml.gz], built.written
    refute_predicate build, :full
    Mapitaine.configuration.rebuild_every = nil
    storage.content_by_name["sitemap-manifest.json"] = JSON.generate(manifest)

    assert_empty build.written
  end

  def test_files_of_a_build_that_died_midway_are_removed_by_the_next
    create_post(1)
    build
    create_post(12)
    failing = Class.new(MemoryStorage) do
      def write(name, source_path)
        raise IOError, "disk full" if name == "sitemap.xml"

        super
      end
    end.new
    failing.content_by_name.merge!(storage.content_by_name)
    Mapitaine.configuration.storage = failing

    assert_raises(IOError) { Mapitaine.build }
    assert failing.content_by_name.key?("sitemap-post-00001.xml.gz")
    Post.where(id: 12).delete_all
    @storage = MemoryStorage.new
    storage.content_by_name.merge!(failing.content_by_name)
    Mapitaine.configuration.storage = storage
    built = build

    assert_equal %w[sitemap-post-00001.xml.gz], built.deleted
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

  def test_a_language_moved_to_a_host_of_its_own_rewrites_everything
    create_post(1)
    build
    Mapitaine.configuration.host_by_locale = {fr: "https://fr.example.com"}
    built = build

    assert_equal %w[sitemap-post-00000.xml.gz sitemap-page.xml.gz], built.written
    assert_includes storage.xml("sitemap-post-00000.xml.gz"), "<url><loc>https://fr.example.com/fr/posts/1</loc><lastmod>2026-01-01T12:00:00Z</lastmod>" \
      '<xhtml:link rel="alternate" hreflang="en" href="https://example.com/en/posts/1"/>' \
      '<xhtml:link rel="alternate" hreflang="fr" href="https://fr.example.com/fr/posts/1"/>' \
      '<xhtml:link rel="alternate" hreflang="x-default" href="https://example.com/en/posts/1"/></url>'
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

    assert_includes xml, "<loc>https://example.com/en/posts?title=Tom%20&amp;%20%22Jerry%22%20%3C3</loc>"
    assert_includes xml, "<image:image><image:loc>https://example.com/images/1.jpg</image:loc></image:image>" \
                         "<image:image><image:loc>https://cdn.example.com/1.jpg?a=1&amp;b=2</image:loc></image:image></url>"
  end

  def test_a_url_written_by_hand_is_percent_encoded
    create_post(1)
    by_hand = Class.new(PostSitemap) do
      url { |_post, locale| "/#{locale}/Café\u0001 d" + "\xE9j\xE0?q=100%25&off=100%" }
      images { ["//cdn.example.com/a b.jpg"] }
    end
    Mapitaine.configuration.sources = [by_hand]
    build
    xml = storage.xml("sitemap-post-00000.xml.gz")

    assert_includes xml, "<loc>https://example.com/en/Caf%C3%A9%01%20d%E9j%E0?q=100%25&amp;off=100%25</loc>"
    assert_includes xml, "<image:loc>https://cdn.example.com/a%20b.jpg</image:loc>"
  end

  def test_rails_locales_become_hreflang_codes_and_x_default_is_found_whatever_its_type
    create_post(1, languages: "en,pt_BR")
    strings = Class.new(PostSitemap) { locales { |post| post.languages.split(",") } }
    Mapitaine.configuration.sources = [strings]
    Mapitaine.configuration.x_default = :en
    build
    xml = storage.xml("sitemap-post-00000.xml.gz")

    assert_includes xml, %(hreflang="pt-BR" href="https://example.com/pt_BR/posts/1")
    assert_includes xml, %(hreflang="x-default" href="https://example.com/en/posts/1")
  end

  def test_two_languages_sharing_a_url_list_it_once
    create_post(1, languages: "en,fr,de")
    shared = Class.new(PostSitemap) { url { |post, locale| post_url(post, locale: (locale == :de) ? :en : locale) } }
    Mapitaine.configuration.sources = [shared]
    built = build
    xml = storage.xml("sitemap-post-00000.xml.gz")

    assert_equal 2, built.url_count
    assert_equal 2, xml.scan("<loc>").size
    assert_includes xml, %(hreflang="de" href="https://example.com/en/posts/1")
  end

  def test_lastmods_are_written_in_utc_and_the_index_takes_the_latest
    create_post(1)
    create_post(2)
    create_post(3)
    tokyo = Time.new(2026, 1, 15, 10, 0, 0, "+09:00")
    stamps = {1 => "2026-01-15T10:00+09:00", 2 => "2026-01-15T05:00:00Z", 3 => "2026-02-30T05:00:00Z"}
    zoned = Class.new(PostSitemap) { lastmod { |post| stamps.fetch(post.id) } }
    Mapitaine.configuration.sources = [zoned, Class.new(PageSitemap) { lastmod { tokyo } }]
    build

    assert_includes storage.xml("sitemap-post-00000.xml.gz"), "<lastmod>2026-01-15T01:00:00Z</lastmod>"
    assert_includes storage.xml("sitemap-post-00000.xml.gz"), "<url><loc>https://example.com/en/posts/3</loc><xhtml:link"
    assert_includes storage.xml("sitemap.xml"), "sitemap-post-00000.xml.gz</loc><lastmod>2026-01-15T05:00:00Z</lastmod>"
    assert_includes storage.xml("sitemap-page.xml.gz"), "<lastmod>2026-01-15T01:00:00Z</lastmod>"
    assert_equal 9 * 3600, tokyo.utc_offset
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
    assert_equal ["build.mapitaine", {full: true, result: built}], events.last
    events.clear
    built = build

    assert_equal ["build.mapitaine", {full: false, result: built}], events.last
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
