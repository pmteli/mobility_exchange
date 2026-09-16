ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
load Rails.root.join("db/seeds/mobility_exchange.rb")
class ActiveSupport::TestCase
  # Schema requires SERIALIZABLE at the outermost transaction. Tests use unique IDs
  # and a dedicated disposable database, so Rails must not wrap them in transactions.
  self.use_transactional_tests = false
  def create_user(role: "public", verified: true)
    Workflow.run do
      user = User.create!(email: "test-#{SecureRandom.hex(8)}@example.test", first_name: "Test", last_name: "User", auth_subject: "test:#{SecureRandom.uuid}", account_status: verified ? "active" : "pending", email_verified_at: verified ? Time.current : nil)
      Credential.create!(user: user, password: "correct horse battery staple", password_confirmation: "correct horse battery staple")
      UserRole.create!(user_id: user.id, role_id: role, assigned_by: user.id)
      user
    end
  end
  def create_item(actor)
    Workflow.run do
      category = EquipmentCategory.first!
      type = EquipmentType.create!(category_id: category.id, name: "Test type #{SecureRandom.hex(8)}")
      location = Location.create!(name: "Test Center", pickup_enabled: true, dropoff_enabled: true)
      Equipment.create!(inventory_number: Workflow.reference("TEST"), name: "Test wheelchair", type_id: type.id, location_id: location.id, condition: "good", acquisition_kind: "legacy", received_at: Time.current, created_by: actor.id, updated_by: actor.id, private_notes: "PRIVATE-NEVER-PUBLIC")
    end
  end
  def make_available(actor, item)
    %w[awaiting_inspection inspected awaiting_sanitization sanitized cataloged available].each { |target| ProcessEquipment.call(actor, item.id, target, "Test processing evidence") }
    item.reload
  end
end
