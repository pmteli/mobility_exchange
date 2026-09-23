require "test_helper"
class GoogleOauthTest < ActiveSupport::TestCase
  test "claims require verified email subject and matching nonce" do
    claims = {"sub" => "123", "email" => "person@example.test", "email_verified" => true, "nonce" => "expected"}
    assert_equal "123", GoogleOauth.validate_claims(claims, nonce: "expected")["sub"]
    assert_raises(GoogleOauth::Invalid) { GoogleOauth.validate_claims(claims, nonce: "wrong") }
    assert_raises(GoogleOauth::Invalid) { GoogleOauth.validate_claims(claims.merge("email_verified" => false), nonce: "expected") }
    assert_raises(GoogleOauth::Invalid) { GoogleOauth.validate_claims(claims.merge("sub" => ""), nonce: "expected") }
    assert_raises(GoogleOauth::Invalid) { GoogleOauth.validate_claims(claims.merge("email" => "bad"), nonce: "expected") }
  end
  test "token exchange verifies signature issuer audience and expiry with real signed tokens" do
    old_id = ENV["GOOGLE_CLIENT_ID"]
    old_secret = ENV["GOOGLE_CLIENT_SECRET"]
    old_uri = ENV["GOOGLE_REDIRECT_URI"]
    ENV.update("GOOGLE_CLIENT_ID" => "test-client", "GOOGLE_CLIENT_SECRET" => "test-secret", "GOOGLE_REDIRECT_URI" => "https://example.test/auth/google/callback")
    key = OpenSSL::PKey::RSA.generate(2048)
    jwk = JWT::JWK.new(key)
    source = Google::Auth::IDTokens::StaticKeySource.from_jwk_set({keys: [jwk.export.merge(alg: "RS256")]})
    original_keys = Google::Auth::IDTokens.method(:oidc_key_source)
    original_http = Net::HTTP.method(:start)
    Google::Auth::IDTokens.define_singleton_method(:oidc_key_source) { source }
    claims = {"iss" => "https://accounts.google.com", "aud" => "test-client", "sub" => "123",
      "email" => "person@example.test", "email_verified" => true, "nonce" => "expected", "exp" => 5.minutes.from_now.to_i}
    exchange = lambda do |payload, signing_key = key|
      token = JWT.encode(payload, signing_key, "RS256", kid: jwk.kid)
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.define_singleton_method(:body) { {id_token: token}.to_json }
      http = Object.new
      http.define_singleton_method(:request) { |request| response }
      Net::HTTP.define_singleton_method(:start) { |*args, **options, &block| block.call(http) }
      GoogleOauth.identity(code: "code", verifier: "verifier", nonce: "expected")
    end
    assert_equal "123", exchange.call(claims)["sub"]
    assert_raises(GoogleOauth::Invalid) { exchange.call(claims.merge("aud" => "another-client")) }
    assert_raises(GoogleOauth::Invalid) { exchange.call(claims.merge("iss" => "https://attacker.test")) }
    assert_raises(GoogleOauth::Invalid) { exchange.call(claims.merge("exp" => 1.hour.ago.to_i)) }
    assert_raises(GoogleOauth::Invalid) { exchange.call(claims, OpenSSL::PKey::RSA.generate(2048)) }
    assert_raises(GoogleOauth::Invalid) { exchange.call(claims.merge("nonce" => "wrong")) }
  ensure
    Google::Auth::IDTokens.define_singleton_method(:oidc_key_source, original_keys) if original_keys
    Net::HTTP.define_singleton_method(:start, original_http) if original_http
    {"GOOGLE_CLIENT_ID" => old_id, "GOOGLE_CLIENT_SECRET" => old_secret, "GOOGLE_REDIRECT_URI" => old_uri}.each { |k,v| v ? ENV[k] = v : ENV.delete(k) }
  end

end
