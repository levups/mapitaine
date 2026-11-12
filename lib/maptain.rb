# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/inflections"
require "active_support/notifications"
require "date"
require "digest"
require "fileutils"
require "json"
require "net/http"
require "time"
require "tmpdir"
require "uri"
require "zlib"

require_relative "maptain/version"
require_relative "maptain/errors"
require_relative "maptain/storage/local"
require_relative "maptain/storage/active_storage"
require_relative "maptain/storage/null"
require_relative "maptain/configuration"
require_relative "maptain/page"
require_relative "maptain/xml"
require_relative "maptain/source"
require_relative "maptain/shard_writer"
require_relative "maptain/manifest"
require_relative "maptain/index_now"
require_relative "maptain/builder"
require_relative "maptain/railtie" if defined?(Rails::Railtie)

module Maptain
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
