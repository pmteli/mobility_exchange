require "test_helper"
class TestUserSeedsTest < ActiveSupport::TestCase
  test "test user seed has exact roles and is repeatable without resetting passwords" do
    previous = ENV["TEST_USERS_PASSWORD"]
    ENV["TEST_USERS_PASSWORD"] = "seed-test-password-2026"
    load Rails.root.join("db/seeds/test_users.rb")
    users = User.where("auth_subject LIKE ?", "seed:mobility-test:%")
    assert_equal 19, users.count
    assert_equal 19, users.where(account_status: "active").where.not(email_verified_at: nil).count
    { "donor" => 3, "volunteer" => 5, "recipient" => 10 }.each do |role, count|
      assert_equal count, users.where("community_roles @> ARRAY[?]::text[]", role).count
    end
    assert_equal 1, UserRole.where(user_id: users.select(:id), role_id: "admin").count
    assert_equal 5, Volunteer.where(user_id: users.select(:id), approval_status: "approved").count
    digest = User.find("seed-test-administrator-1").credential.password_digest
    ENV["TEST_USERS_PASSWORD"] = "another-seed-password"
    assert_no_difference "User.count" do
      load Rails.root.join("db/seeds/test_users.rb")
    end
    assert_equal digest, User.find("seed-test-administrator-1").credential.reload.password_digest
  ensure
    ENV["TEST_USERS_PASSWORD"] = previous
  end
end
