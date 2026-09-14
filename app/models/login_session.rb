class LoginSession < MobilityRecord
  self.table_name = "mobility_exchange.login_sessions"
  belongs_to :user
end
