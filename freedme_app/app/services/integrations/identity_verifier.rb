module Integrations
  class IdentityVerifier
    def verify(evidence_id:)
      raise NotConfigured, "IdentityVerifier is not configured; no external request was sent."
    end
  end
end
