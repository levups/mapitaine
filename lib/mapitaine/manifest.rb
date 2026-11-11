# frozen_string_literal: true

module Mapitaine
  # What the last build wrote: for each shard of each source, its fingerprint and its files.
  class Manifest
    attr_reader :built_at, :digest, :shards_by_source

    def self.read(storage, name)
      json = storage.read(name)
      return new unless json

      stored = JSON.parse(json)
      new(digest: stored["digest"], built_at: Time.iso8601(stored["built_at"]), shards_by_source: stored["sources"])
    rescue JSON::ParserError, ArgumentError, TypeError
      # A manifest we cannot read is a manifest we do not have: the build starts over and replaces it.
      new
    end

    def initialize(digest: nil, built_at: nil, shards_by_source: {})
      @digest = digest
      @built_at = built_at
      @shards_by_source = shards_by_source
    end

    def shard(source, key)
      shards_by_source.dig(source, key)
    end

    def record(source, key, fingerprint:, files:)
      (shards_by_source[source] ||= {})[key] = {"fingerprint" => fingerprint, "files" => files}
    end

    def files
      shards_by_source.each_value.flat_map { |shards| shards.each_value.flat_map { |shard| shard["files"] } }
    end

    def file_names
      files.map { |file| file["name"] }
    end

    def to_json(*)
      JSON.pretty_generate("digest" => digest, "built_at" => built_at.utc.iso8601, "sources" => shards_by_source)
    end
  end
end
