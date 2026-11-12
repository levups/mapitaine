# frozen_string_literal: true

module Mapitaine
  # Tells Bing, Yandex, Seznam and Naver which URLs changed: https://www.indexnow.org/documentation
  class IndexNow
    ENDPOINT = URI("https://api.indexnow.org/indexnow")
    MAX_URLS_PER_REQUEST = 10_000
    HEADERS = {"Content-Type" => "application/json; charset=utf-8"}.freeze
    # The last four: a proxy that refuses, and a reply that is not HTTP or not the gzip it claims to be.
    # Net::HTTPBadResponse is no ProtocolError.
    NETWORK_ERRORS = [SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError,
      Net::ProtocolError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Zlib::Error].freeze

    def initialize(key:, key_path: nil, transport: Net::HTTP.method(:post))
      @key = key
      @key_path = key_path
      @transport = transport
    end

    # status: the HTTP status, or the class of the network error.
    Reply = Data.define(:urls, :status) do
      def accepted?
        status.is_a?(Integer) && status.between?(200, 299)
      end
    end

    # One reply per request of up to 10,000 URLs, all of one host as IndexNow asks. Once the endpoint cannot be
    # reached, the requests that follow, of this host or another, do not each wait for a timeout of their own.
    def submit(host, urls)
      urls.each_slice(MAX_URLS_PER_REQUEST).map do |batch|
        Reply.new(urls: batch, status: @network_error || post(host, batch))
      end
    end

    private

    def post(host, urls)
      body = {host: URI.parse(host).host, key: @key, keyLocation: @key_path && "#{host}#{@key_path}", urlList: urls}.compact
      @transport.call(ENDPOINT, JSON.generate(body), HEADERS).code.to_i
    rescue *NETWORK_ERRORS => exception
      @network_error = exception.class.name
    end
  end
end
