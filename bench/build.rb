# frozen_string_literal: true

# bundle exec ruby [--yjit] bench/build.rb: a full build of 30,000 records in 24 languages, a build with nothing
# new, then one after three records changed; then the same full build with sitemap_generator.

require "bundler/setup"
require "active_record"
require "benchmark"
require "mapitaine"
require "sitemap_generator"

RECORD_COUNT = 30_000
LOCALES = %i[ar bg cs da de el en es fi fr he hu it ja ko nb nl pl pt ro sk sv tr zh].freeze
I18n.available_locales = LOCALES

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :posts do |table|
    table.string :slug, null: false
    table.timestamps
  end
end

class Post < ActiveRecord::Base
end

class PostSitemap < Mapitaine::Source
  scope { Post.all }
  url { |post, locale| "/#{locale}/posts/#{post.slug}" }
end

yesterday = Time.now - 86_400
Post.insert_all(Array.new(RECORD_COUNT) do |number|
  {slug: "a-fairly-long-post-slug-number-#{number}", created_at: yesterday, updated_at: yesterday}
end)

Dir.mktmpdir do |directory|
  Mapitaine.configure do |config|
    config.host = "https://www.example.com"
    config.locales = LOCALES
    config.x_default = :en
    config.storage = Mapitaine::Storage::Local.new(directory)
    config.sources = [PostSitemap]
  end

  built = nil
  puts format("Full build          %8.3f s", Benchmark.realtime { built = Mapitaine.build })
  sizes = Dir[File.join(directory, "*.gz")].map { |path| [File.size(path), Zlib.gunzip(File.binread(path)).bytesize] }
  puts format("                    %d URLs in %d files, the largest %.1f MiB, %.1f MiB gzipped in all",
    built.url_count, sizes.size, sizes.map(&:last).max / 1_048_576.0, sizes.sum(&:first) / 1_048_576.0)
  puts format("Nothing new         %8.3f s", Benchmark.realtime { Mapitaine.build })
  Post.where(id: [5, 17_000, 17_001]).update_all(updated_at: Time.now)
  puts format("3 records changed   %8.3f s", Benchmark.realtime { built = Mapitaine.build })
  puts format("                    %d files written, %d kept", built.written.size, built.kept.size)
end

# The same sitemap with sitemap_generator, which lists every URL again at each build.
Dir.mktmpdir do |directory|
  SitemapGenerator::Sitemap.default_host = "https://www.example.com"
  SitemapGenerator::Sitemap.public_path = directory
  SitemapGenerator::Sitemap.include_root = false
  SitemapGenerator::Sitemap.verbose = false
  time = Benchmark.realtime do
    SitemapGenerator::Sitemap.create do
      Post.find_each do |post|
        hrefs = LOCALES.to_h { |locale| [locale, "https://www.example.com/#{locale}/posts/#{post.slug}"] }
        alternates = hrefs.map { |locale, href| {lang: locale, href: href} } << {lang: "x-default", href: hrefs[:en]}
        hrefs.each_value { |href| add href, lastmod: post.updated_at, alternates: alternates }
      end
    end
  end
  puts format("sitemap_generator   %8.3f s, at every build", time)
  puts format("                    %d URLs in %d files", SitemapGenerator::Sitemap.link_count, Dir[File.join(directory, "*.gz")].size)
end
