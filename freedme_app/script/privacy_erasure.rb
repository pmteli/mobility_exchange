# Run with bin/rails runner script/privacy_erasure.rb MODE ACCOUNT_UUID ADMIN_UUID [PLAN_BASENAME]
# Review files contain private data. Never commit, email or upload them.
begin
mode, account_id, reviewer_id, basename = ARGV
account = Account.find(account_id)
reviewer = Account.find(reviewer_id)
service = Privacy::Erasure.new(account, reviewer)
root = Privacy::ManagedBackup.directory
case mode
when 'plan'
  path = root.join("#{SecureRandom.uuid}.review.json")
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0600) do |file|
    file.write(JSON.pretty_generate(service.plan))
  end
  puts "Review file: #{path.basename}. Review every text value and photo; remove only the requesting user's information."
  puts 'Confirm the three review flags only after shared content, media and application logs are checked.'
when 'execute'
  raise Privacy::Erasure::Error, 'Use a generated review filename.' unless basename.to_s.match?(/\A[0-9a-f-]{36}\.review\.json\z/)
  path = root.join(basename)
  raise Privacy::Erasure::Error, 'Review files may not be symlinks.' if path.symlink?
  service.execute!(JSON.parse(File.read(path)))
  puts 'Application erasure completed. Shared records remain; old managed backups and review files were removed.'
else
  raise Privacy::Erasure::Error, 'Choose plan or execute.'
end

rescue StandardError => error
  warn "Privacy maintenance failed (#{error.class.name}). No completion is claimed; review the request securely before retrying."
  exit 1
end
