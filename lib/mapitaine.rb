# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/inflections"
require "active_support/notifications"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "tmpdir"
require "uri"
require "zlib"

require_relative "mapitaine/version"
require_relative "mapitaine/errors"
require_relative "mapitaine/storage/local"
require_relative "mapitaine/storage/active_storage"
require_relative "mapitaine/storage/null"
require_relative "mapitaine/configuration"
require_relative "mapitaine/page"
require_relative "mapitaine/xml"
require_relative "mapitaine/source"
require_relative "mapitaine/shard_writer"
require_relative "mapitaine/manifest"
require_relative "mapitaine/index_now"
require_relative "mapitaine/builder"
require_relative "mapitaine/railtie" if defined?(Rails::Railtie)

module Mapitaine
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration
      @configuration = nil
    end

    # full: true rewrites every file, whatever the manifest of the last build says.
    def build(full: false)
      Builder.new(configuration).build(full:)
    end

    # Renders every sitemap without writing or submitting anything, and returns what looks wrong in them.
    def check
      Builder.new(configuration, storage: Storage::Null.new, submit: false).build(full: true).warnings
    end
  end
end
