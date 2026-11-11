# frozen_string_literal: true

module Mapitaine
  module Storage
    class Null
      def read(_name)
      end

      def write(_name, _source_path)
      end

      def delete(_name)
      end
    end
  end
end
