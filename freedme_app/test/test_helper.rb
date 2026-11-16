ENV["RAILS_ENV"] ||= "test"
ENV["SMS_PROVIDER"] = "simulated"
require_relative "../config/environment"
require "rails/test_help"

ActiveRecord::Migration.check_pending_migrations

# Never contact AWS from tests; service tests override these stubbed responses.
class ActiveSupport::TestCase
  setup do
    ENV.delete("TEXTRACT_ENABLED")
    ENV["REKOGNITION_ENABLED"] = "true"
    ENV["REKOGNITION_POLICY"] = "review_only"
    ENV["REKOGNITION_EQUIPMENT_ENABLED"] = "false"
    Aws.config[:rekognition] = {stub_responses: true}
  end
end

class ActionDispatch::IntegrationTest
  def login_staff_account(account)
    password = 'Test-only staff password 2026!'
    credential = StaffCredential.find_by(account_id: account.id)
    unless credential
      contact = AccountContact.create!(account_id: account.id, kind: 'email', lookup_hmac: Journeys::Support.digest("#{account.id}@example.test"), value_ciphertext: Journeys::Support.encrypt("#{account.id}@example.test"), key_version: 'fictional-seed-v1')
      credential = StaffCredential.create!(account_id: account.id, email_contact_id: contact.id, username: "staff-#{account.id}", password: password,
        first_name_ciphertext: Journeys::Support.encrypt('Test'), last_name_ciphertext: Journeys::Support.encrypt('Staff'),
        mfa_secret_ciphertext: Journeys::Support.encrypt(ROTP::Base32.random), key_version: 'fictional-seed-v1', session_version: SecureRandom.hex(32))
    end
    travel 31.seconds if credential.last_totp_at && credential.last_totp_at >= Time.current.to_i - 30
    post staff_sign_in_path, params: {identifier: credential.username, password: password}
    assert_redirected_to staff_verify_path
    post staff_verify_path, params: {code: Staff::Authentication.totp(credential).now}
    assert_response :redirect
  end
end
