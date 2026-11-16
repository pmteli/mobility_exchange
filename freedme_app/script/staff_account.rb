# Run with bin/rails runner script/staff_account.rb; passwords never go in shell arguments.
require 'io/console'
abort 'Run this command as the server OS superuser (root).' unless Process.uid.zero?
abort 'Use an interactive terminal.' unless $stdin.tty?
def ask(label, secret: false)
  print "#{label}: "
  value = secret ? $stdin.noecho(&:gets) : $stdin.gets
  puts if secret
  abort 'Cancelled.' unless value
  value.chomp
end
begin
  operation = ask('Action (create/reset)')
  if operation == 'create'
    fields = {email: ask('Email'), username: ask('Username'), first_name: ask('First name'), last_name: ask('Last name'), role: ask('Role (moderator/administrator)')}
  elsif operation == 'reset'
    identifier = ask('Existing staff email or username')
  else
    abort 'Unknown action.'
  end
  password = ask('New password (8+ characters, maximum 72 bytes)', secret: true)
  abort 'Passwords do not match.' unless password == ask('Confirm password', secret: true)
  credential = operation == 'create' ? Staff::Provisioner.create!(**fields, password: password) : Staff::Provisioner.reset!(identifier, password)
  puts "Staff account ready: #{credential.username}. Sign in at /staff/sign-in and enroll an authenticator."
rescue ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
  warn "Unable to provision staff account: #{e.is_a?(ArgumentError) ? e.message : 'Check for duplicate username/email or invalid account details.'}"
  exit 1
end
