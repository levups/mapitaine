# Mapitaine

Mapitaine writes the XML sitemaps of a Rails site in many languages, and rewrites only the files whose pages
changed since the last build.

You describe each kind of page once, as a small class that names its records, their URLs and their languages:

```ruby
# app/sitemaps/product_sitemap.rb
class ProductSitemap < Mapitaine::Source
  scope { Product.published }
  url { |product, locale| product_url(product, locale:) }
end
```

Mapitaine does the rest: one `<url>` per language, each listing every language of the page and the default one,
files that never outgrow what the protocol allows, the sitemap index, and a build you can run every hour.

The guide and the benchmarks are also on the website: <https://levups.github.io/mapitaine/>.

## Why Mapitaine

Mapitaine was written for a site of 30,000 pages in 24 languages, 720,000 URLs, where regenerating everything
on each run is time spent on pages that did not change. It works differently from older generators in a few ways:

- A page is one record in several languages, not a list of unrelated URLs. The `hreflang` links come from that:
  every language lists all the others and itself, which search engines require before they trust any of them.
- Each file holds a fixed range of ids, so a record stays in the same file from one build to the next. A build
  asks the database one question per source, the count, the sum of the ids and the latest change of each range,
  and rewrites only the files whose answer moved. No callback in your models: `update_all`, imports and deletions
  are seen too, and a full build once a week catches what leaves those numbers alone.
- `lastmod` is the only hint search engines still read, so it is the date your content changed, in the files
  and in the index. `priority` and `changefreq`, which Google ignores, are not written.
- Search engines are told through [IndexNow](https://www.indexnow.org) which URLs changed. The ping endpoints
  older gems call have been closed.
- It never requests your pages. What it checks, it checks on the data it writes.

On 30,000 records in 24 languages (SQLite in memory, Ruby 3.3.6 without YJIT, `bench/build.rb`):

| Build | Time | Files written |
|---|---|---|
| Everything, 720,000 URLs | 31.9 s | 55 (17 MiB gzipped) |
| Nothing new | 0.01 s | 0 |
| 3 records changed | 1.0 s | 2 |

Its only runtime dependency is Active Support.

## Installation

```ruby
gem "mapitaine"
```

Mapitaine needs Ruby 3.3 and Rails 8.0, or newer.

## Configuration

```ruby
# config/initializers/mapitaine.rb
Mapitaine.configure do |config|
  config.host = "https://www.example.com"
  config.locales = %i[en fr de]   # default: I18n.available_locales
  config.x_default = :en          # the language of hreflang="x-default"; none when left out
end
```

Then tell crawlers where the index is, in `public/robots.txt`:

```
Sitemap: https://www.example.com/sitemap.xml
```

When the sitemaps are served from elsewhere (`config.sitemaps_url`, see [Storage](#storage)), that line names
the index there: a sitemap on another host, or in a folder of the site, may list the pages of the site only
when its `robots.txt` points to it.

## Sources

A source is a class in `app/sitemaps`. Its blocks run in an object that has your route helpers, already set to
`config.host`.

```ruby
class ProductSitemap < Mapitaine::Source
  # The records: an Active Record relation. Add the `includes` your other blocks need.
  scope { Product.published.includes(:photos) }

  # The URL of a record in a language. A path gets the host; nil leaves that language out.
  url { |product, locale| product_url(product, locale:) }

  # The languages a record exists in. Without it, every configured language.
  locales { |product| product.translated_locales }

  # The column that holds the date the content changed. Default: updated_at.
  lastmod :content_updated_at

  # Image URLs, for Google Images.
  images { |product| product.photos.map(&:url) }
end
```

A page in one language gets no `hreflang` link. A page that does not exist in the `x_default` language gets
no `x-default` link. A Rails locale such as `pt_BR` is written `hreflang="pt-BR"`, and two languages that share
a URL list it once.

A URL your block writes by hand is percent-encoded: spaces, accents and control characters cannot break a file.

### When the date depends on more than one column

`lastmod` also takes a block. The build then needs to know what to watch in the database, as an SQL expression:

```ruby
class ProductSitemap < Mapitaine::Source
  scope { Product.published }
  url { |product, locale| product_url(product, locale:) }
  lastmod { |product| [product.updated_at, product.reviewed_at].compact.max }
  fingerprint "GREATEST(products.updated_at, COALESCE(products.reviewed_at, products.updated_at))"
end
```

A column that moves when the content does not, such as an `updated_at` touched by a view counter, makes every
build rewrite files for nothing and tells search engines a date that is not true. Give such a model a column of
its own for content changes.

### Pages that are not records

The scope can be any list. Such a source is one file, rendered at each build and published when it differs:

```ruby
class PageSitemap < Mapitaine::Source
  scope { %i[root about contact] }
  url { |page, locale| public_send(:"#{page}_url", locale:) }
end
```

### Files

A source named `ProductSitemap` writes `sitemap-product-00000.xml.gz`, `sitemap-product-00001.xml.gz` and so
on, one per range of ids; `slug "products"` changes the middle part. The size of a range comes from the number
of languages, so that a file stays under 50,000 URLs and 50 MiB: 50,000 ids with one language, 554 with 24.
`shard_size 1_000` sets it yourself. A range that still outgrows a file continues in
`sitemap-product-00000-2.xml.gz`.

The model needs an integer primary key.

## Building

```sh
bin/rails mapitaine:build     # rewrite the files whose records changed
bin/rails mapitaine:rebuild   # rewrite everything
```

`Mapitaine.build` does the same from Ruby and returns what it did (`full`, `written`, `kept`, `deleted`,
`url_count`, `submitted`, `warnings`). Run it on a schedule, every night or every hour. With Solid Queue:

```yaml
# config/recurring.yml
production:
  sitemap:
    command: "Mapitaine.build"
    schedule: every hour
```

### How a build decides

For each source, one query groups the records by range of ids and returns the count, the sum of the ids and the
latest change of each. A range whose answer is the one the last build stored keeps its file. The others are
rendered again, and a file that comes out the same is not uploaded (a full build uploads every file). In the index, a file that changed takes the
latest `lastmod` it holds, or the time of the build when a record left it, so that crawlers read it again.

Some changes leave those numbers alone: `update_columns`, a change in another table that the `url`, `locales` or
`images` blocks read, a new `url` block, a file someone removed from the storage. Name the other table in
`fingerprint`, or `touch` the record from it. For the rest, a full build comes once a week by itself:

```ruby
config.rebuild_every = 1.day   # default: a week; nil leaves it to mapitaine:rebuild
```

After deploying a change to a `url` block, run `mapitaine:rebuild` rather than wait.

A build notes the files it is about to add in `sitemap-manifest.json`, its memory of what each file held, then
writes the sitemap files, then the index, then removes the files no range fills any more, then writes the
manifest again. A build that fails midway is repaired by the next one. Changing the host, the languages, the
size of a range or the version of Mapitaine rewrites everything it moves once.

## Storage

Files go to `public/` by default.

### Through Active Storage

An app that already uses Active Storage can send the sitemaps through one of its services, with the credentials
it already has. Give them a service of their own in `config/storage.yml`, in the bucket you want:

```yaml
sitemaps:
  service: S3
  bucket: example-sitemaps
  region: eu-west-3
  public: true
  access_key_id: <%= Rails.application.credentials.dig(:aws, :access_key_id) %>
  secret_access_key: <%= Rails.application.credentials.dig(:aws, :secret_access_key) %>
```

```ruby
Mapitaine.configure do |config|
  config.storage = Mapitaine::Storage::ActiveStorage.new(:sitemaps, prefix: "sitemaps")
  config.sitemaps_url = "https://cdn.example.com/sitemaps"   # where those files are served from
end
```

No blob is created: the files keep their names as keys, and nothing is written to the database. Any service
works that serves a key at a stable URL: S3, Google Cloud Storage, Azure, a mirror of them. The Disk service
does not, it scatters keys in subfolders: keep the default for files on disk.

A storage is any object with `read(name)`, `write(name, path)` and `delete(name)`.

## IndexNow

```ruby
config.index_now_key = "c1f0e2b4a6d84f3e9b7a5c3d1e0f2a4b"   # yours: 8 to 128 characters, a-z, A-Z, 0-9 and -
```

Each build then publishes the key as `<key>.txt` at the root of the site, and sends, from the files it rewrote,
the URLs whose `lastmod` is later than the previous build, and those that appeared or went away whatever their
`lastmod`. The first build sends nothing, and only URLs on `config.host` are sent.

When the sitemaps are served from elsewhere (`config.sitemaps_url`), the key cannot follow them: IndexNow reads
it on the site. Put `<key>.txt` in `public/` and set `config.index_now_key_location` to its URL; a build warns
until you do.

A refusal or an endpoint that cannot be reached is a warning, never a failed build: the URLs it did not take are
kept in the manifest and sent again with the next build.

## Checking

```sh
bin/rails mapitaine:check
```

It renders every sitemap without publishing or submitting anything, and fails on:

- a URL outside `config.host`, listed twice in a source, or longer than 2,048 characters, and a page whose
  languages all share one URL;
- an `hreflang` that is not a language code (`en`, `pt-BR`, `zh-Hant`, `es-419`);
- a `lastmod` in the future, or one that is not a W3C date, which is then left out;
- an index with more than the 50,000 files it may hold.

A build reports the same, for the files it rewrites, in `warnings`.

## Instrumentation

`build.mapitaine` wraps a build, with `full` and `result` in its payload; `shard.mapitaine` wraps each file
range it renders, with `source` and `shard`.

```ruby
ActiveSupport::Notifications.subscribe("build.mapitaine") do |event|
  built = event.payload[:result]
  Rails.logger.info "Sitemap: #{built.written.size} files written in #{event.duration.round} ms"
end
```

## Not there yet

Video and news sitemaps, models without an integer primary key, and building several ranges in parallel.

## Development

```sh
bundle exec rake test
bundle exec rubocop
bundle exec ruby bench/build.rb
bundle exec rake docs:highlight   # after editing a code block in docs/
```

## License

MIT. See [LICENSE](LICENSE).
