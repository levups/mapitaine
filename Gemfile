# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "actionpack"
  gem "activerecord"
  gem "activestorage"
  gem "activesupport"
  gem "minitest"
  gem "rake"
  gem "rubocop", require: false
  gem "rubocop-performance", require: false
  gem "sqlite3"
  gem "standard", require: false
end

group :development do
  gem "benchmark" # bench/build.rb: a bundled gem since Ruby 4.0, which Rails 8.1 no longer brings
  gem "rouge", "5.1.0" # pinned: docs:highlight:check compares its output with the committed pages
  gem "sitemap_generator" # bench/build.rb compares a full build with it
end
