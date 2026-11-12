# frozen_string_literal: true

module Mapitaine
  # Tells Bing, Yandex, Seznam and Naver which URLs changed: https://www.indexnow.org/documentation
  class IndexNow
    ENDPOINT = URI("https://api.indexnow.org/indexnow")
    MAX_URLS_PER_REQUEST = 10_000
    HEADERS = {"Content-Type" => "application/json; charset=utf-8"}.freeze

    def initialize(key:, key_path: nil, transport: Net::HTTP.method(:post))
      @key = key
      @key_path = key_path
      @transport = transport
    end

    # status: the HTTP status, or the class of what the transport raised.
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

    # Whatever the transport raises is a reply that did not come, from a refused connection to a body that is
    # not HTTP: no list of classes covers them all, and the sitemaps are published, so none may fail the build.
    def post(host, urls)
      body = {host: URI.parse(host).host, key: @key, keyLocation: @key_path && "#{host}#{@key_path}", urlList: urls}.compact
      body = JSON.generate(body)
      begin
        @transport.call(ENDPOINT, body, HEADERS).code.to_i
      rescue => exception
        @network_error = exception.class.name
      end
    end
  end
end
