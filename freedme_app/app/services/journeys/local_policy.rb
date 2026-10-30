# Synthetic settings for local workflows, NOT approval of DEC01–DEC06 or launch.
module Journeys
  class LocalPolicy
    def self.prepare!(moderator)
      Support.guard!
      policy = PolicyVersion.find_or_create_by!(kind: "local_simulation", version: "v1") do |p|
        p.assign_attributes(content_sha256: Digest::SHA256.hexdigest("SIMULATION ONLY"), content_object_key: "simulation/no-real-policy",
          configuration: { simulation_only: true, availability_days: 30, identity_days: 30 },
          approved_by: moderator.id, approved_at: Time.current, effective_at: 1.day.ago)
      end
      Category.find_each do |category|
        EquipmentConfiguration.find_or_create_by!(policy_id: policy.id, category_id: category.id, code: "simulation") do |c|
          c.assign_attributes(allowed: true, guidance_policy_id: policy.id)
        end
      end
      policy
    end
    def self.policy!
      Support.guard!
      moderator = Account.joins("JOIN freedme.account_roles roles ON roles.account_id=accounts.id").find_by!(roles: {role: "moderator"})
      prepare!(moderator)
    end
    def self.area!(policy, locality)
      zip = locality.to_s[/\b\d{5}\b/] || "94536"
      ServiceArea.find_or_create_by!(policy_id: policy.id, zip_code: zip) do |a|
        a.assign_attributes(county: "SIMULATED", city: locality, donor_eligible: true, recipient_eligible: true)
      end
    end
    def self.enable_transaction_fixtures!
      policy = policy!
      PilotControl.first!.update!(privacy_policy_id: policy.id, loan_policy_id: policy.id,
        evidence_collection_enabled: true, loans_enabled: true)
      policy
    end
  end
end
