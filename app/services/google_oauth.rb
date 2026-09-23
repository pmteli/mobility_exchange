require "net/http"
require "googleauth/id_tokens"

# Authorization-code flow: tokens remain server-side and are never persisted.
class GoogleOauth
  class Invalid < StandardError; end
  def self.enabled?
    %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET GOOGLE_REDIRECT_URI].all? { |key| ENV[key].present? }
  end

  def self.authorization_url(state:, nonce:, verifier:)
    "https://accounts.google.com/o/oauth2/v2/auth?" + URI.encode_www_form(
      client_id: ENV.fetch("GOOGLE_CLIENT_ID"), redirect_uri: ENV.fetch("GOOGLE_REDIRECT_URI"),
      response_type: "code", scope: "openid email profile", state: state, nonce: nonce,
      code_challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false),
      code_challenge_method: "S256", prompt: "select_account", access_type: "online")
  end

  def self.identity(code:, verifier:, nonce:)
    uri = URI("https://oauth2.googleapis.com/token")
    request = Net::HTTP::Post.new(uri)
    request.set_form_data(code: code, code_verifier: verifier, client_id: ENV.fetch("GOOGLE_CLIENT_ID"),
      client_secret: ENV.fetch("GOOGLE_CLIENT_SECRET"), redirect_uri: ENV.fetch("GOOGLE_REDIRECT_URI"), grant_type: "authorization_code")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) { |http| http.request(request) }
    raise Invalid unless response.is_a?(Net::HTTPSuccess)
    token = JSON.parse(response.body).fetch("id_token")
    claims = Google::Auth::IDTokens.verify_oidc(token, aud: ENV.fetch("GOOGLE_CLIENT_ID"))
    validate_claims(claims, nonce: nonce)
  rescue Google::Auth::IDTokens::VerificationError, Google::Auth::IDTokens::KeySourceError,
      JSON::ParserError, KeyError, Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError
    raise Invalid, "Google sign-in could not be verified. Please try again."
  end

  def self.validate_claims(claims, nonce:)
    raise Invalid unless nonce.present? && claims["nonce"].is_a?(String) &&
      ActiveSupport::SecurityUtils.secure_compare(claims["nonce"], nonce)
    raise Invalid unless claims["email_verified"] == true && claims["sub"].is_a?(String) &&
      claims["sub"].present? && claims["sub"].length <= 255 && claims["email"].is_a?(String) &&
      claims["email"].length <= 254 && claims["email"].match?(URI::MailTo::EMAIL_REGEXP)
    if claims["azp"].present? && claims["azp"] != ENV.fetch("GOOGLE_CLIENT_ID")
      raise Invalid
    end
    { "sub" => claims["sub"], "email" => claims["email"].strip.downcase,
      "first_name" => claims["given_name"].to_s.first(100), "last_name" => claims["family_name"].to_s.first(100) }
  end
end
