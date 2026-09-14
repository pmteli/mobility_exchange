class User < MobilityRecord
  self.table_name = "mobility_exchange.users"
  self.primary_key = "id"
  has_one :credential, foreign_key: :user_id
  has_many :user_roles, foreign_key: :user_id
  has_one :donor
  has_one :recipient
  has_one :volunteer, foreign_key: :user_id
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }
  validates :first_name, :last_name, presence: true, length: { maximum: 100 }
  before_validation { self.email = email.to_s.strip.downcase }
  def name
    [first_name, last_name].join(" ")
  end
  def admin?
    user_roles.exists?(role_id: "admin")
  end
  def allowed?(permission)
    return false unless account_status == "active" && email_verified_at.present?
    RolePermission.where(role_id: user_roles.select(:role_id), permission_id: permission).exists? ||
      UserPermissionGrant.where(user_id: id, permission_id: permission).where("expires_at IS NULL OR expires_at > ?", Time.current).exists?
  end
end
