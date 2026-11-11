# frozen_string_literal: true

module Mapitaine
  module Storage
    # Sends the files through a service of config/storage.yml, without creating blobs: the sitemaps reuse the
    # credentials of the app, in a bucket of their own when the service names one.
    class ActiveStorage
      # A service name of config/storage.yml, or a service object.
      def initialize(service, prefix: nil)
        @service = service
        @prefix = prefix
      end

      def read(name)
        service.download(key(name))
      rescue ::ActiveStorage::FileNotFoundError
        nil
      end

      def write(name, source_path)
        content_type = CONTENT_TYPE_BY_EXTENSION.fetch(File.extname(name))
        File.open(source_path, "rb") { |file| service.upload(key(name), file, content_type:) }
      end

      def delete(name)
        service.delete(key(name))
      end

      private

      # Looked up at the first call: an initializer runs before Active Storage has read config/storage.yml.
      def service
        @service = ::ActiveStorage::Blob.services.fetch(@service) if @service.is_a?(Symbol) || @service.is_a?(String)
        @service
      end

      def key(name)
        @prefix ? File.join(@prefix, name) : name
      end
    end
  end
end
