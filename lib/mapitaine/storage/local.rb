# frozen_string_literal: true

module Mapitaine
  module Storage
    CONTENT_TYPE_BY_EXTENSION = {
      ".gz" => "application/gzip", ".json" => "application/json", ".txt" => "text/plain", ".xml" => "application/xml"
    }.freeze

    class Local
      def initialize(directory)
        @directory = directory.to_s
      end

      def read(name)
        path = File.join(@directory, name)
        File.read(path) if File.exist?(path)
      end

      # Copied beside the target, then renamed: a crawler never downloads half a file.
      def write(name, source_path)
        FileUtils.mkdir_p(@directory)
        target = File.join(@directory, name)
        partial = "#{target}.#{Process.pid}.partial"
        FileUtils.cp(source_path, partial)
        File.rename(partial, target)
      end

      def delete(name)
        FileUtils.rm_f(File.join(@directory, name))
      end
    end
  end
end
