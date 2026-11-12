# Mapitaine

Rails sitemaps that rewrite only what changed. Each build asks your database what moved since the last one and
leaves every other file alone, so it runs hundreds of times faster than regenerating everything. You describe
each kind of page once, in a small class; Mapitaine writes one URL per language with its `hreflang` links.

```ruby
# app/sitemaps/product_sitemap.rb
class ProductSitemap < Mapitaine::Source
  scope { Product.published }
  url { |product, locale| product_url(product, locale:) }
end
```

```sh
bin/rails mapitaine:build
```

That writes `public/sitemap.xml` and the files it lists. Run it again an hour later: if nothing changed, it
takes a few milliseconds and writes nothing.

Website, guide and benchmarks: <https://levups.github.io/mapitaine/>.

## Is it for you?

Mapitaine was written for one site: 30,000 products in 24 languages, 720,000 URLs. It will help most if yours
looks a bit like that, with records in a database, translated, and changing a little every day.

A site of a few hundred pages in one language does not need it: [sitemap_generator](https://github.com/kjvarga/sitemap_generator)
or a view that lists them will do. Mapitaine is also young (0.1), so read [what it does not do yet](#not-there-yet)
before you switch.

## What it does differently

- **A page is a record in several languages.** Every language of it lists all the others and itself as
  `hreflang` links, which search engines require before they trust any of them. You never write those links.
- **Files that stay put.** Each file holds a fixed range of ids, so a record lands in the same file at every
  build, and crawlers only fetch again the files that changed.
- **Builds that skip what did not move.** One query per source asks the database the count, the sum of the ids
  and the latest change of each range. No callback in your models, so `update_all`, imports and deletions are
  seen too.
- **Dates that are true.** `lastmod` is the date your content changed. `priority` and `changefreq`, which
  Google ignores, are not written.
- **IndexNow instead of pings.** Bing, Yandex, Seznam and Naver are told which URLs changed. The ping endpoints
  that older gems call have been closed.

Its only runtime dependency is Active Support.

## How long it takes

`bench/build.rb` builds the same sitemap with Mapitaine and with sitemap_generator, on the same machine. When a
few records changed, Mapitaine is about 400 times faster: it rewrites 2 files where sitemap_generator writes them
all again. Once a week, a full build rewrites everything to catch what the database numbers cannot see; that one
is 15 times faster.

On 30,000 records in 24 languages (SQLite in memory, Ruby 4.0.9 without YJIT, an Apple M5 Max, median of 3
runs; seconds depend on the machine, the ratios hold from one to the next):

| Build | Mapitaine | sitemap_generator | Faster | Files written |
|---|---|---|---|---|
| Nothing new | 0.004 s | 150 s | (nothing to write) | 0 |
| 3 records changed | 0.35 s | 150 s | 430× | 2 |
| Everything, 720,000 URLs | 9.9 s | 150 s | 15× | 55 (16.5 MiB gzipped) |

The URLs there are plain strings. With route helpers and a real database every build takes longer, and the gap
narrows a little: on a copy of a production app's database, 560,000 URLs took 35 s in full (13 times faster) and 2.8 s after
three products changed (170 times faster), where sitemap_generator took 468 s. The [benchmarks page](https://levups.github.io/mapitaine/benchmarks.html) explains
where the time goes.

## Getting started

1. Add the gem. It needs Ruby 3.3 and Rails 8.0, or newer.

   ```ruby
   gem "mapitaine"
   ```

2. Name the host of the site:

   ```ruby
   # config/initializers/mapitaine.rb
   Mapitaine.configure do |config|
     config.host = "https://www.example.com"
     config.locales = %i[en fr de]   # default: I18n.available_locales
     config.x_default = :en          # the language of hreflang="x-default"; none when left out
   end
   ```

3. Write one class per kind of page in `app/sitemaps`, like `ProductSitemap` above. Its blocks have your route
   helpers.

4. Look at what it would write, without writing it:

   ```sh
   bin/rails mapitaine:check
   ```

   It fails on a URL outside the site, a URL listed twice, a date in the future, and a few other
   [mistakes](#checking).

5. Build, and tell crawlers where the index is, in `public/robots.txt`:

   ```sh
   bin/rails mapitaine:build
   ```

   ```
   Sitemap: https://www.example.com/sitemap.xml
   ```

6. Run it on a schedule. With Solid Queue:

   ```yaml
   # config/recurring.yml
   production:
     sitemap:
       command: "Mapitaine.build"
       schedule: every hour
   ```

The rest of this README is the guide: languages, dates, files, storage on S3 and the like, IndexNow.

## Coming from sitemap_generator

| sitemap_generator | Mapitaine |
|---|---|
| `config/sitemap.rb`, one `add` per URL | one `Mapitaine::Source` per kind of page, in `app/sitemaps` |
| `alternates:` written by hand for each URL | `hreflang` links written from `config.locales`, or a source's `locales` |
| `default_host` | `config.host`, and `config.host_by_locale` for one host per language |
| `rake sitemap:refresh` | `bin/rails mapitaine:build`, which rewrites only what changed |
| `lastmod:` | `updated_at` by default, or `lastmod :column` |
| `priority:`, `changefreq:` | left out: Google ignores them |
| pinging search engines | IndexNow, with `config.index_now_key` |
| `sitemaps_host`, adapters | `config.sitemaps_url`, and any Active Storage service |

sitemap_generator names its index `sitemap.xml.gz`, Mapitaine `sitemap.xml`: change the `Sitemap:` line of
`robots.txt`, and delete the old files once the first build has written the new ones.

## Sources

A source is a class in `app/sitemaps`. Its blocks run in an object that has your route helpers, already set to
`config.host`, or in the `url` block to the host of the language being written. That block also runs with its
language as `I18n.locale`, so a slug read from a translated attribute comes out in the language of its page; a
language that is not in `I18n.available_locales` runs in the app's.

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

The model needs an integer primary key: files are cut by ranges of ids.

### Pages that are not records

The scope can be any list. Such a source is one file, rendered at each build and published when it differs:

```ruby
class PageSitemap < Mapitaine::Source
  scope { %i[root about contact] }
  url { |page, locale| public_send(:"#{page}_url", locale:) }
end
```

## Languages

Every record gets one URL per language of `config.locales`, or of its source's `locales` block. Each `<url>`
then lists every language of its page, itself included:

```xml
<url>
  <loc>https://www.example.com/fr/products/42</loc>
  <lastmod>2026-11-03T09:12:44Z</lastmod>
  <xhtml:link rel="alternate" hreflang="en" href="https://www.example.com/en/products/42"/>
  <xhtml:link rel="alternate" hreflang="fr" href="https://www.example.com/fr/products/42"/>
  <xhtml:link rel="alternate" hreflang="x-default" href="https://www.example.com/en/products/42"/>
</url>
```

A page in one language gets no `hreflang` link. A page that does not exist in the `x_default` language gets
no `x-default` link. A Rails locale such as `pt_BR` is written `hreflang="pt-BR"`, and two languages that share
a URL list it once.

A URL your block writes by hand is percent-encoded: spaces, accents and control characters cannot break a file.

### One host per language

When some languages are served from a host of their own, name those hosts:

```ruby
config.host = "https://www.example.com"
config.host_by_locale = {fr: "https://fr.example.com", de: "https://de.example.com"}
```

The other languages stay on `config.host`, and so does the index. The `robots.txt` of every host names that one
index: a sitemap may list the pages of a host only when that host's `robots.txt` points to it.

## The date of a page

`lastmod` is read from `updated_at`. Name another column when the content has its own: `lastmod
:content_updated_at`.

A column that moves when the content does not, such as an `updated_at` touched by a view counter, makes every
build rewrite files for nothing and tells search engines a date that is not true. Give such a model a column of
its own for content changes.

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

## Files

A source named `ProductSitemap` writes `sitemap-product-00000.xml.gz`, `sitemap-product-00001.xml.gz` and so
on, one per range of ids; `slug "products"` changes the middle part, `config.filename` the first. The size of a
range comes from the number of languages, so that a file stays under 50,000 URLs and 50 MiB: 50,000 ids with one
language, 554 with 24. `shard_size 1_000` sets it yourself. A range that still outgrows a file continues in
`sitemap-product-00000-2.xml.gz`.

`sitemap.xml` is the index. It lists every file with the latest `lastmod` it holds, so a crawler fetches again
only the files that changed.

## Building

```sh
bin/rails mapitaine:build     # rewrite the files whose records changed
bin/rails mapitaine:rebuild   # rewrite everything
```

`Mapitaine.build` does the same from Ruby and returns what it did (`full`, `written`, `kept`, `deleted`,
`url_count`, `submitted`, `warnings`).

### How a build decides

For each source, one query groups the records by range of ids and returns the count, the sum of the ids and the
latest change of each. A range whose answer is the one the last build stored keeps its file. The others are
rendered again, and a file that comes out the same is not uploaded (a full build uploads every file). In the
index, a file that changed takes the latest `lastmod` it holds, or the time of the build when a record left it,
so that crawlers read it again.

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

The `Sitemap:` line of `robots.txt` then names the index there: a sitemap on another host, or in a folder of the
site, may list the pages of the site only when its `robots.txt` points to it.

A storage is any object with `read(name)`, `write(name, path)` and `delete(name)`.

## IndexNow

[IndexNow](https://www.indexnow.org) tells Bing, Yandex, Seznam and Naver that a URL changed. Google does not
take part. Choose a key of 8 to 128 characters among a-z, A-Z, 0-9 and -:

```ruby
config.index_now_key = "c1f0e2b4a6d84f3e9b7a5c3d1e0f2a4b"
```

Each build then publishes the key as `<key>.txt` at the root of the site, and sends, from the files it rewrote,
the URLs whose `lastmod` is later than the previous build, and those that appeared or went away whatever their
`lastmod`. The first build sends nothing, nor does a new configuration beyond the pages whose `lastmod` moved,
and only URLs on the hosts of the site are sent.

When the sitemaps are served from elsewhere (`config.sitemaps_url`), the key cannot follow them: IndexNow reads
it on the site. Put `<key>.txt` in `public/` and set `config.index_now_key_location` to its path,
`"/<key>.txt"`; a build warns until you do.

With one host per language, every host must serve the key: IndexNow reads it on the host of the URLs it is given.

A refusal or an endpoint that cannot be reached is a warning, never a failed build: the URLs it did not take are
kept in the manifest and sent again with the next build.

## Checking

```sh
bin/rails mapitaine:check
```

It renders every sitemap without publishing or submitting anything, and fails on:

- a URL outside the hosts of the site, listed twice in a source, or longer than 2,048 characters, and a page whose
  languages all share one URL;
- an `hreflang` that is not a language code (`en`, `pt-BR`, `zh-Hant`, `es-419`);
- a `lastmod` in the future, or one that is not a W3C date, which is then left out;
- an index with more than the 50,000 files it may hold.

When many URLs of a source make the same mistake, one line names the first and counts the others. A build
reports the same, for the files it rewrites, in `warnings`.

Mapitaine never requests a page of the site. Whether a URL answers 200 or carries a `noindex` is what Search
Console reports, from the visits crawlers make anyway.

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
bundle exec ruby bench/build.rb   # also builds the same sitemap with sitemap_generator: a few minutes
bundle exec rake docs:highlight   # after editing a code block in docs/
```

## License

MIT. See [LICENSE](LICENSE).

Made by [Level UP Solutions](https://github.com/levups).
