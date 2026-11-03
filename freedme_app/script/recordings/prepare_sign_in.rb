# FR003/026: exercise the real mobile + OTP flow at every recorded role switch.
abort 'Isolated recording database only' unless ENV['FREEDME_RECORDING_MODE']=='true' && ApplicationRecord.connection.select_value('SELECT current_database()')=='freedme_recording_demo'
# Retain completed challenges, but age their creation time in this disposable
# sandbox so a recording does not need to wait for hourly OTP rate limits.
# Unconsumed challenges and the production authentication service are untouched.
AuthChallenge.where.not(consumed_at: nil).where("created_at > ?", 2.hours.ago).update_all(created_at: 2.hours.ago)
