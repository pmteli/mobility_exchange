class UpdateRegistrationWelcomeNotification < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO freedme.notification_templates(code, version, body)
      VALUES ('registration_welcome', 2, 'Welcome to FreeDME {display_name}. Take the next step to either donate, lend or find a mobility equipment for yourself or your loved ones. Visit https://freedme.org')
      ON CONFLICT DO NOTHING;
    SQL
  end

  def down
    execute "DELETE FROM freedme.notification_templates WHERE code = 'registration_welcome' AND version = 2"
  end
end
