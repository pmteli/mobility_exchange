namespace :privacy do
  desc 'Apply exchange retention and purge expired identity source images'
  task maintain: :environment do
    Privacy::ExchangeRetention.run!
    IdentityDocuments::Vault.purge!
    Privacy::Reporting.run!
    puts 'Privacy maintenance completed.'
  end
  desc 'Create an encrypted database backup excluding identity source images'
  task backup: :environment do
    path = Privacy::ManagedBackup.create!
    puts "Encrypted backup created: #{path.basename}"
  end
end
