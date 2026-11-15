module Integrations
  class OtpVerifier
    def verify(challenge_id:, code:)
      challenge = AuthChallenge.find(challenge_id)
      return false if challenge.consumed_at || challenge.invalidated_at || challenge.expires_at <= Time.current
      Journeys::Authentication.valid_code?(challenge, code)
    end
  end
end
