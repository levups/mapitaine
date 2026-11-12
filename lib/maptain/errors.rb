# frozen_string_literal: true

module Maptain
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class SourceError < Error; end
end
