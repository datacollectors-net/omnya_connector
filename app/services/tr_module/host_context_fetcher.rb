require "json"
require "net/http"
require "openssl"

module TrModule
  class HostContextFetcher
    class Error < StandardError; end

    def self.call(token:, context_endpoint:, allowed_origins:)
      raise Error, "missing_token" if token.blank?
      raise Error, "missing_context_endpoint" if context_endpoint.blank?

      uri = URI.parse(context_endpoint)
      endpoint_origin = origin_for(uri)

      unless allowed_origins.include?(endpoint_origin)
        raise Error, "untrusted_context_endpoint"
      end

      request = Net::HTTP::Get.new(uri)
      request["Authorization"] = "Bearer #{token}"
      request["Accept"] = "application/json"

      http_options = { use_ssl: uri.scheme == "https" }
      # Allow self-signed host certificates during local development only.
      if Rails.env.development? && uri.scheme == "https"
        http_options[:verify_mode] = OpenSSL::SSL::VERIFY_NONE
      end

      response = Net::HTTP.start(uri.host, uri.port, **http_options) do |http|
        http.request(request)
      end

      raise Error, "unauthorized" if response.code.to_i == 401
      raise Error, "context_request_failed" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    rescue URI::InvalidURIError, JSON::ParserError => e
      raise Error, e.message
    end

    def self.origin_for(uri)
      default_port = (uri.scheme == "https" && uri.port == 443) || (uri.scheme == "http" && uri.port == 80)
      return "#{uri.scheme}://#{uri.host}" if default_port

      "#{uri.scheme}://#{uri.host}:#{uri.port}"
    end

    private_class_method :origin_for
  end
end
