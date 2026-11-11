# frozen_string_literal: true

module Mapitaine
  # One kind of page. A subclass names its records, their URLs and their languages:
  #
  #   class ProductSitemap < Mapitaine::Source
  #     scope { Product.published }
  #     url { |product, locale| product_url(product, locale:) }
  #   end
  class Source
    # The protocol allows 50 MiB a file, uncompressed. Shards aim lower: the sizes below are estimates.
    TARGET_BYTES_PER_FILE = 40 * 1024 * 1024
    BYTES_PER_URL_ESTIMATE = 150
    BYTES_PER_ALTERNATE_ESTIMATE = 120
    MYSQL_ADAPTERS = %w[mysql2 trilogy].freeze
    SLUG_FORMAT = /\A[a-z0-9][a-z0-9_-]*\z/
    # A source that is not an Active Record relation is one shard, rendered at each build.
    WHOLE = "all"

    class << self
      def inherited(subclass)
        super
        subclass.instance_variable_set(:@definitions, definitions.dup)
      end

      def definitions
        @definitions ||= {lastmod: :updated_at}
      end

      # The records, as an Active Record relation or any enumerable.
      def scope(&block)
        definitions[:scope] = block
      end

      def scope?
        definitions.key?(:scope)
      end

      # The URL of a record in a language, or nil when it has none. A path is completed with the host.
      def url(&block)
        definitions[:url] = block
      end

      # The languages a record exists in. Without it, every configured language.
      def locales(&block)
        definitions[:locales] = block
      end

      # A column, or a block for anything else. With a block on a relation, name what changes with it in
      # `fingerprint`: the column alone no longer tells a build what moved.
      def lastmod(column = nil, &block)
        definitions[:lastmod] = block || column
      end

      def images(&block)
        definitions[:images] = block
      end

      # The SQL expression whose greatest value changes whenever a record's sitemap entry does.
      def fingerprint(sql)
        definitions[:fingerprint] = sql
      end

      # How many consecutive ids share a file.
      def shard_size(count)
        definitions[:shard_size] = Integer(count)
      end

      def slug(name = nil)
        definitions[:slug] = name.to_s if name
        return definitions[:slug] if definitions[:slug]

        self.name ? self.name.demodulize.underscore.delete_suffix("_sitemap") : superclass.slug
      end
    end

    attr_reader :configuration

    def initialize(configuration)
      @configuration = configuration
      return if self.class.slug.match?(SLUG_FORMAT)

      raise SourceError, "#{self.class.name}'s slug #{self.class.slug.inspect} must be lowercase letters, digits, - and _"
    end

    def slug
      self.class.slug
    end

    # What `url` blocks read when they call a route helper.
    def default_url_options
      uri = URI.parse(configuration.host!)
      {host: uri.host, protocol: uri.scheme, port: (uri.port unless uri.port == uri.default_port)}.compact
    end

    # A nil fingerprint means the shard has to be rendered to know whether it changed.
    def fingerprint_by_shard
      return {WHOLE => nil} unless relation?

      relation.reorder(nil).group(shard_sql).pluck(shard_sql, Arel.sql("COUNT(*)"), fingerprint_sql)
        .to_h { |shard, count, latest| [shard.to_i.to_s, "#{count}/#{precise(latest)}"] }
    end

    def each_page(shard)
      return to_enum(:each_page, shard) unless block_given?

      records_of(shard) do |record|
        page = page_for(record)
        yield page unless page.url_by_locale.empty?
      end
    end

    def basename(shard)
      prefix = "#{configuration.filename}-#{slug}"
      (shard == WHOLE) ? prefix : "#{prefix}-#{shard.rjust(5, "0")}"
    end

    private

    def definitions
      self.class.definitions
    end

    def relation
      @relation ||= instance_exec(&definitions.fetch(:scope))
    end

    def relation?
      relation.respond_to?(:find_each) && relation.respond_to?(:group)
    end

    def model
      relation.klass
    end

    def records_of(shard, &)
      return relation.each(&) unless relation?

      first_id = shard.to_i * shard_size
      relation.where(model.primary_key => first_id...(first_id + shard_size)).find_each(&)
    end

    def page_for(record)
      locales = definitions[:locales] ? Array(instance_exec(record, &definitions[:locales])) : configuration.locales
      url_by_locale = locales.filter_map do |locale|
        location = instance_exec(record, locale, &definitions.fetch(:url))
        [locale, absolute(location)] if location
      end
      Page.new(url_by_locale: url_by_locale.to_h, lastmod: lastmod_of(record), images: images_of(record))
    end

    def absolute(location)
      location.start_with?("/") ? "#{configuration.host!}#{location}" : location
    end

    def lastmod_of(record)
      lastmod = definitions[:lastmod]
      return instance_exec(record, &lastmod) if lastmod.respond_to?(:call)

      record.public_send(lastmod) if lastmod && record.respond_to?(lastmod)
    end

    def images_of(record)
      definitions[:images] ? Array(instance_exec(record, &definitions[:images])).map { |location| absolute(location) } : []
    end

    def shard_size
      @shard_size ||= definitions[:shard_size] || default_shard_size
    end

    def default_shard_size
      locale_count = configuration.locales.size
      alternates = (locale_count > 1) ? locale_count + 1 : 0
      bytes_per_record = locale_count * (BYTES_PER_URL_ESTIMATE + alternates * BYTES_PER_ALTERNATE_ESTIMATE)
      [ShardWriter::MAX_URLS_PER_FILE / locale_count, TARGET_BYTES_PER_FILE / bytes_per_record].min.clamp(1..)
    end

    # Two updates in the same second must not look like one.
    def precise(latest)
      latest.respond_to?(:utc) ? latest.utc.iso8601(6) : latest.to_s
    end

    def shard_sql
      @shard_sql ||= begin
        primary_key = model.primary_key
        unless primary_key.is_a?(String) && model.type_for_attribute(primary_key).type == :integer
          raise SourceError, "#{self.class.name} needs a scope whose model has an integer primary key"
        end
        # MySQL's / returns a decimal.
        division = MYSQL_ADAPTERS.include?(model.connection_db_config.adapter) ? "DIV" : "/"
        Arel.sql("#{model.quoted_table_name}.#{model.quoted_primary_key} #{division} #{shard_size}")
      end
    end

    def fingerprint_sql
      column = definitions[:lastmod].is_a?(Symbol) ? definitions[:lastmod] : :updated_at
      expression = definitions[:fingerprint] ||
        "#{model.quoted_table_name}.#{model.adapter_class.quote_column_name(column)}"
      Arel.sql("MAX(#{expression})")
    end
  end
end
