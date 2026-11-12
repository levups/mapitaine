# frozen_string_literal: true

module Maptain
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

    # status: the HTTP status, or the class of the network error.
    Reply = Data.define(:urls, :status) do
      def accepted?
        status.is_a?(Integer) && status.between?(200, 299)
      end
    end

    # One reply per request of up to 10,000 URLs.
    def submit(urls)
      urls.each_slice(MAX_URLS_PER_REQUEST).map do |batch|
        body = {host: @host, key: @key, keyLocation: @key_location, urlList: batch}.compact
        Reply.new(urls: batch, status: @transport.call(ENDPOINT, JSON.generate(body), HEADERS).code.to_i)
      rescue *NETWORK_ERRORS => exception
        Reply.new(urls: batch, status: exception.class.name)
      end
    end
  end
end
