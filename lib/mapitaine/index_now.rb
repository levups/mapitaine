# frozen_string_literal: true

module Mapitaine
  # Tells Bing, Yandex, Seznam and Naver which URLs changed: https://www.indexnow.org/documentation
  class IndexNow
    ENDPOINT = URI("https://api.indexnow.org/indexnow")
    MAX_URLS_PER_REQUEST = 10_000
    HEADERS = {"Content-Type" => "application/json; charset=utf-8"}.freeze
    NETWORK_ERRORS = [SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError].freeze

    def initialize(host:, key:, key_location: nil, transport: Net::HTTP.method(:post))
      @host = URI.parse(host).host
      @key = key
      @key_location = key_location
      @transport = transport
    end

    # Returns how many URLs the endpoint took.
    def submit(urls)
      urls.each_slice(MAX_URLS_PER_REQUEST).sum do |batch|
        body = {host: @host, key: @key, keyLocation: @key_location, urlList: batch}.compact
        response = @transport.call(ENDPOINT, body.to_json, HEADERS)
        response.code.to_i.between?(200, 299) ? batch.size : 0
      end
    end
  end
end
