class PersonalizeListingSubmittedNotification < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO freedme.notification_templates(code, version, body)
      VALUES ('listing_submitted', 2, 'Thank you for offering {item_title} to a neighbor. Your listing is under review. You will be notified when it is published.')
      ON CONFLICT DO NOTHING;
    SQL
  end

  def down
    execute "DELETE FROM freedme.notification_templates WHERE code = 'listing_submitted' AND version = 2"
  end
end
