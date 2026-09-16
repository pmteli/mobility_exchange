require "io/console"
namespace :mobility do
  desc "Create the first administrator with email and password"
  task bootstrap_admin: :environment do
    abort "An admin exists. Use an audited administrator-management process for additional admins." if UserRole.exists?(role_id: "admin")
    email = ENV["ADMIN_EMAIL"] || (print("Admin email: "); STDIN.gets.to_s.strip)
    password = ENV["ADMIN_PASSWORD"] || IO.console&.getpass("Password (8+ characters): ")
    abort "A password is required." if password.blank?
    Workflow.run do
      user = User.create!(email: email, first_name: "Administrator", last_name: "Mobility Exchange", auth_subject: "local:#{SecureRandom.uuid}", account_status: "active", email_verified_at: Time.current)
      Credential.create!(user: user, password: password, password_confirmation: password)
      UserRole.create!(user_id: user.id, role_id: "admin", assigned_by: user.id)
      Audit.record!(user, "admin.bootstrapped", user)
    end
    puts "Administrator created. Sign in with your email and password."
  end
  desc "Create clearly labeled sample inventory; disabled in production"
  task demo: :environment do
    abort "Demo data is disabled in production." if Rails.env.production?
    load Rails.root.join("db/seeds/demo.rb")
  end
  desc "Publish approved legal text: KIND=recipient_waiver|donor_certification VERSION=1 TITLE=... TEXT_FILE=... ACTOR_EMAIL=..."
  task publish_legal: :environment do
    kind, version, title = ENV.fetch("KIND"), ENV.fetch("VERSION"), ENV.fetch("TITLE")
    exact_text = File.read(ENV.fetch("TEXT_FILE"), encoding: "UTF-8")
    abort "The document cannot be empty." if exact_text.blank?
    Workflow.run do
      actor = User.find_by!(email: ENV.fetch("ACTOR_EMAIL").downcase)
      Workflow.authorize!(actor, "content.manage")
      record = LegalDocumentVersion.create!(kind: kind, version: version, title: title, exact_text: exact_text, text_sha256: Digest::SHA256.hexdigest(exact_text), published_at: Time.current, published_by: actor.id)
      active = ActiveLegalDocument.find_or_initialize_by(kind: kind)
      active.update!(version_id: record.id)
      Audit.record!(actor, "legal.published", record)
    end
    puts "Document published. Previous versions and signatures remain unchanged."
  end
  desc "Create a location and equipment type from operator-provided configuration"
  task configure: :environment do
    Workflow.run do
      actor = User.find_by!(email: ENV.fetch("ACTOR_EMAIL").downcase)
      Workflow.authorize!(actor, "settings.manage")
      if ENV["LOCATION_NAME"].present?
        location = Location.create!(name: ENV.fetch("LOCATION_NAME"), address_line1: ENV["ADDRESS"], city: ENV["CITY"], region: ENV["REGION"], postal_code: ENV["POSTAL_CODE"], timezone: ENV.fetch("TIMEZONE", "America/Los_Angeles"), pickup_enabled: true, dropoff_enabled: true)
        Audit.record!(actor, "location.created", location)
        puts "Location ID: #{location.id}"
      end
      if ENV["TYPE_NAME"].present?
        type = EquipmentType.create!(name: ENV.fetch("TYPE_NAME"), category_id: ENV.fetch("CATEGORY_ID"))
        Audit.record!(actor, "equipment_type.created", type)
        puts "Equipment type ID: #{type.id}"
      end
    end
  end
  desc "Deliver up to 50 pending email notifications (development writes tmp/mail)"
  task deliver_notifications: :environment do
    50.times { break unless NotificationDelivery.deliver_one }
  end
end
