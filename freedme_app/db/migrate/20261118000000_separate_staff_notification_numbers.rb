class SeparateStaffNotificationNumbers < ActiveRecord::Migration[8.0]
  def up
    add_column "freedme.account_contacts", :staff_notification, :boolean, null: false, default: false
    execute "UPDATE freedme.account_contacts SET staff_notification=true WHERE kind='mobile' AND account_id IN (SELECT account_id FROM freedme.account_roles WHERE role IN ('moderator','administrator'))"
    execute "DROP INDEX freedme.one_live_phone_owner"
    execute "CREATE UNIQUE INDEX one_live_phone_owner ON freedme.account_contacts(lookup_hmac) WHERE kind='mobile' AND revoked_at IS NULL AND NOT staff_notification"
    %w[sms_deliveries simulated_sms_messages].each do |table|
      add_column "freedme.#{table}", :recipient_account_id, :uuid
    end
    execute "UPDATE freedme.sms_deliveries s SET recipient_account_id=c.account_id FROM freedme.account_contacts c WHERE c.kind='mobile' AND c.revoked_at IS NULL AND c.lookup_hmac=s.recipient_hmac"
    # Existing simulations contain plaintext destinations; associate them before
    # shared numbers become possible so account inboxes retain their history.
    AccountContact.where(kind: "mobile", revoked_at: nil).find_each do |contact|
      phone = Journeys::Support.decrypt(contact.value_ciphertext)
      execute "UPDATE freedme.simulated_sms_messages SET recipient_account_id=#{connection.quote(contact.account_id)} WHERE recipient=#{connection.quote(phone)} AND recipient_account_id IS NULL"
    end
  end
  def down
    raise ActiveRecord::IrreversibleMigration, "Shared phone numbers must be resolved before restoring global uniqueness."
  end
end
