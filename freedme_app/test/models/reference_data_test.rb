require "test_helper"

class ReferenceDataTest < ActiveSupport::TestCase
  test "reference seeds are repeatable and leave pilot gates disabled" do
    load Rails.root.join("db/seeds.rb")
    template_count = NotificationTemplate.count
    load Rails.root.join("db/seeds.rb")
    assert_equal 7, Category.count
    assert_equal template_count, NotificationTemplate.count
    assert_equal 11, NotificationTemplate.distinct.count(:code)
    controls = PilotControl.first!
    refute controls.loans_enabled
    refute controls.evidence_collection_enabled
    assert_nil controls.privacy_policy_id
    assert_nil controls.loan_policy_id
  end
end
