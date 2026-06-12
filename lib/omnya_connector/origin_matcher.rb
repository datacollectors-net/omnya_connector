require "uri"

module OmnyaConnector
  module OriginMatcher
    module_function

    def origin_allowed?(origin, allowed_origins)
      normalized_origin = normalize_origin(origin)
      return false if normalized_origin.nil?

      Array(allowed_origins).any? do |allowed_origin|
        origin_rule_matches?(normalized_origin, allowed_origin)
      end
    end

    def origin_rule_matches?(normalized_origin, allowed_origin)
      rule = allowed_origin.to_s.strip
      return false if rule.empty?

      if wildcard_rule?(rule)
        wildcard_rule_matches?(normalized_origin, rule)
      else
        normalize_origin(rule) == normalized_origin
      end
    end

    def wildcard_rule?(origin_rule)
      origin_rule.include?("*")
    end

    def wildcard_rule_matches?(normalized_origin, wildcard_rule)
      wildcard_match = wildcard_rule.match(/\Ahttps:\/\/\*\.([a-z0-9.-]+)(?::(\d+))?\z/i)
      return false unless wildcard_match

      wildcard_host = wildcard_match[1].downcase
      wildcard_port = wildcard_match[2]
      origin_uri = URI.parse(normalized_origin)
      origin_host = origin_uri.host.to_s.downcase

      # Wildcards only match subdomains, never the apex domain.
      return false unless origin_host.end_with?(".#{wildcard_host}")

      wildcard_port.nil? ? default_port?(origin_uri) : origin_uri.port.to_s == wildcard_port
    rescue URI::InvalidURIError
      false
    end

    def normalize_origin(origin)
      raw_origin = origin.to_s.strip
      return nil if raw_origin.empty?

      uri = URI.parse(raw_origin)
      return nil unless uri.scheme && uri.host

      scheme = uri.scheme.downcase
      host = uri.host.downcase

      standard_port = default_port?(uri)
      standard_port ? "#{scheme}://#{host}" : "#{scheme}://#{host}:#{uri.port}"
    rescue URI::InvalidURIError
      nil
    end

    def default_port?(uri)
      (uri.scheme == "https" && uri.port == 443) || (uri.scheme == "http" && uri.port == 80)
    end
    private_class_method :default_port?
  end
end
