# Explicit opt-in only. Fictional accounts must never be seeded on the live site.
unless Rails.env.test? || Rails.env.development? ||
       (ENV["DEPLOYMENT_STAGE"] == "test" && ENV["APP_HOST"] == "test.mobilityexchange.org")
  raise "Test users are restricted to development and the designated AWS test site."
end
password = ENV.fetch("TEST_USERS_PASSWORD")
raise "TEST_USERS_PASSWORD must contain 8–72 characters" unless (8..72).cover?(password.length)

Workflow.run do
  { "administrator" => 1, "donor" => 3, "volunteer" => 5, "recipient" => 10 }.each do |role, count|
    count.times do |index|
      number = index + 1
      id = "seed-test-#{role}-#{number}"
      email = "#{role}#{number}@example.test"
      subject = "seed:mobility-test:#{role}:#{number}"
      user = User.find_or_initialize_by(id: id)
      raise "Seed ID is owned by a different account: #{id}" if user.persisted? && user.auth_subject != subject
      user.assign_attributes(email: email, first_name: "Test #{role.titleize}", last_name: number.to_s,
        auth_subject: subject, account_status: "active", email_verified_at: user.email_verified_at || Time.current,
        community_roles: role == "administrator" ? [] : [role])
      user.save!
      # Preserve existing passwords on repeat runs.
      Credential.create!(user: user, password: password, password_confirmation: password) unless user.credential
      UserRole.find_or_create_by!(user_id: user.id, role_id: "public") { |r| r.assigned_by = "seed-test-administrator-1" }
      if %w[administrator volunteer].include?(role)
        UserRole.find_or_create_by!(user_id: user.id, role_id: role == "administrator" ? "admin" : "volunteer") { |r| r.assigned_by = "seed-test-administrator-1" }
      end
      case role
      when "donor", "recipient"
        klass = role == "donor" ? Donor : Recipient
        record = klass.find_or_initialize_by(user_id: user.id)
        record.assign_attributes(first_name: user.first_name, last_name: user.last_name, email: user.email, city: "San Jose", region: "CA")
        record.save!
      when "volunteer"
        record = Volunteer.find_or_initialize_by(user_id: user.id)
        record.assign_attributes(approval_status: "approved", approved_by: "seed-test-administrator-1", approved_at: record.approved_at || Time.current, skills: "Fictional test volunteer")
        record.save!
      end
    end
  end
end
puts "Verified test accounts ready: 3 donors, 5 approved volunteers, 10 recipients, 1 administrator. Existing passwords preserved."
