# frozen_string_literal: true

module Mapitaine
  module Storage
    # Needs the aws-sdk-s3 gem, which Mapitaine does not install.
    class S3
      # put_options go to every put_object call: acl:, cache_control:, storage_class:…
      def initialize(bucket:, prefix: nil, client: nil, **put_options)
        require "aws-sdk-s3"
        @bucket = bucket
        @prefix = prefix
        @client = client || Aws::S3::Client.new
        @put_options = put_options
      end

      def read(name)
        @client.get_object(bucket: @bucket, key: key(name)).body.read
      rescue Aws::S3::Errors::NoSuchKey
        nil
      end

      def write(name, source_path)
        content_type = CONTENT_TYPE_BY_EXTENSION.fetch(File.extname(name))
        File.open(source_path, "rb") do |file|
          @client.put_object(bucket: @bucket, key: key(name), body: file, content_type:, **@put_options)
        end
      end

      def delete(name)
        @client.delete_object(bucket: @bucket, key: key(name))
      end

      private

      def key(name)
        @prefix ? File.join(@prefix, name) : name
      end
    end
  end
end
