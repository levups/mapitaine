# frozen_string_literal: true

require "minitest/autorun"
require "action_dispatch"
require "active_record"
require "active_support/core_ext/kernel/reporting"
require "maptain"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :posts do |table|
    table.string :title, null: false
    table.string :languages, null: false, default: "en,fr"
    table.boolean :published, null: false, default: true
    table.datetime :reviewed_at
    table.timestamps
  end

  create_table :tokens, id: :string do |table|
    table.timestamps
  end
end

class Post < ActiveRecord::Base
  scope :published, -> { where(published: true) }
end

class Token < ActiveRecord::Base
end

ROUTES = ActionDispatch::Routing::RouteSet.new
ROUTES.draw do
  scope "(:locale)" do
    resources :posts, only: :show
    get "about", to: "pages#about", as: :about
  end
end
Maptain::Source.include(ROUTES.url_helpers)

class PostSitemap < Maptain::Source
  scope { Post.published }
  url { |post, locale| post_url(post, locale:) }
  locales { |post| post.languages.split(",").map(&:to_sym) }
  shard_size 10
end

class PageSitemap < Maptain::Source
  scope { %i[about] }
  url { |page, locale| public_send(:"#{page}_path", locale:) }
  lastmod { Date.new(2026, 1, 15) }
end

class MemoryStorage
  attr_reader :content_by_name, :writes, :deletions

  def initialize
    @content_by_name = {}
    @writes = []
    @deletions = []
  end

  def read(name)
    content_by_name[name]
  end

  def write(name, source_path)
    writes << name
    content_by_name[name] = File.binread(source_path)
  end

  def delete(name)
    deletions << name
    content_by_name.delete(name)
  end

  def xml(name)
    content = content_by_name.fetch(name)
    name.end_with?(".gz") ? Zlib.gunzip(content) : content
  end

  def forget_calls
    writes.clear
    deletions.clear
  end
end

class MaptainTest < Minitest::Test
  LONG_AGO = Time.utc(2026, 1, 1, 12)

  attr_reader :storage

  def setup
    Post.delete_all
    Maptain.reset_configuration
    @storage = MemoryStorage.new
    Maptain.configure do |config|
      config.host = "https://example.com"
      config.locales = %i[en fr]
      config.x_default = :en
      config.storage = storage
      config.sources = [PostSitemap, PageSitemap]
    end
  end

  def create_post(id, **attributes)
    Post.create!(id:, title: "Post #{id}", created_at: LONG_AGO, updated_at: LONG_AGO, **attributes)
  end

  def build(...)
    storage.forget_calls
    Maptain.build(...)
  end
end
