module OmnyaConnector
  # Adds the `Partitioned` attribute to the Rails session cookie.
  #
  # This enables CHIPS (Cookies Having Independent Partitioned State), which
  # allows the session cookie to work in third-party iframe contexts even when
  # the browser has third-party cookie blocking enabled (Chrome 120+, Safari).
  #
  # Without this, the browser silently discards SameSite=None session cookies set
  # by /module_context, so subsequent requests to Rails controllers arrive with no
  # session and resolve to autonomous/development fallback values.
  class PartitionedCookieMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      add_partitioned_to_session_cookie!(headers)
      [ status, headers, body ]
    end

    private

    def add_partitioned_to_session_cookie!(headers)
      set_cookie = headers["Set-Cookie"]
      return unless set_cookie

      session_key = session_cookie_key
      cookies = set_cookie.is_a?(Array) ? set_cookie : set_cookie.split("\n")

      patched = cookies.map do |cookie|
        if cookie.start_with?("#{session_key}=") && !cookie.include?("Partitioned")
          "#{cookie}; Partitioned"
        else
          cookie
        end
      end

      headers["Set-Cookie"] = patched.join("\n")
    end

    def session_cookie_key
      @session_cookie_key ||= Rails.application.config.session_options[:key]
    end
  end
end
