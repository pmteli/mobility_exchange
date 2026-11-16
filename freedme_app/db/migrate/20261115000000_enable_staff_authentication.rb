class EnableStaffAuthentication < ActiveRecord::Migration[8.1]
  def change
    change_column_null 'freedme.staff_credentials', :mfa_enrolled_at, true
    add_column 'freedme.staff_credentials', :username, :string
    add_index 'freedme.staff_credentials', :username, unique: true
    add_column 'freedme.staff_credentials', :failed_attempts, :integer, null: false, default: 0
    add_column 'freedme.staff_credentials', :locked_until, :datetime
    add_column 'freedme.staff_credentials', :last_totp_at, :bigint
    add_column 'freedme.staff_credentials', :session_version, :string, null: false, default: ''
  end
end
