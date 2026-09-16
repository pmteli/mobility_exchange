class Credential < MobilityRecord
  self.table_name = "mobility_exchange.credentials"
  self.primary_key = "user_id"
  belongs_to :user
  has_secure_password
  encrypts :mfa_secret
  validates :password, length: { minimum: 8, maximum: 72 }, allow_nil: true
  before_create { self.token_nonce ||= SecureRandom.hex(32) }
end
