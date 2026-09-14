class AddLocalAuthentication < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TABLE mobility_exchange.credentials (
        user_id TEXT PRIMARY KEY REFERENCES mobility_exchange.users(id),
        password_digest TEXT NOT NULL, mfa_secret TEXT, last_otp_at BIGINT,
        token_nonce TEXT NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE TABLE mobility_exchange.login_sessions (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES mobility_exchange.users(id),
        expires_at TIMESTAMPTZ NOT NULL, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      CREATE INDEX ON mobility_exchange.login_sessions (user_id);
      REVOKE ALL ON mobility_exchange.credentials, mobility_exchange.login_sessions FROM PUBLIC;
    SQL
  end
  def down
    drop_table "mobility_exchange.login_sessions"
    drop_table "mobility_exchange.credentials"
  end
end
