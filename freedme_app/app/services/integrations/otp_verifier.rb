module Integrations
  class OtpVerifier
    def verify(challenge_id:, code:)
      raise NotConfigured, "OtpVerifier is not configured; no external request was sent."
    end
  end
end
