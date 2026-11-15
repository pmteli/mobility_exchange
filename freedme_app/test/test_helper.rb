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
