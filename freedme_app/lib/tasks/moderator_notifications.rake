namespace :moderator_notifications do
  desc 'Show moderator email/SMS alert states without personal contact details'
  task status: :environment do
    puts "Email: #{ListingReviewAlert.group(:email_state).count}"
    puts "SMS: #{ListingReviewAlert.group(:sms_state).count}"
    ListingReviewAlert.where(email_state: %w[failed sending missing_contact]).or(
      ListingReviewAlert.where(sms_state: 'missing_contact_or_consent')).find_each do |alert|
      puts "Alert #{alert.id}: account=#{alert.account_id} revision=#{alert.revision_id} email=#{alert.email_state} sms=#{alert.sms_state}"
    end
  end
end
