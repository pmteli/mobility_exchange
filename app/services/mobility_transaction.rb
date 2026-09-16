# frozen_string_literal: true

# All reads deciding an operation's writes must occur inside this block.
# Never perform email delivery, payments, or other irreversible side effects here.
class MobilityTransaction
  MAX_ATTEMPTS = 5

  def self.call(max_attempts: MAX_ATTEMPTS, &operation)
    unless max_attempts.is_a?(Integer) && max_attempts.positive?
      raise ArgumentError, "max_attempts must be a positive integer"
    end
    raise ArgumentError, "a block is required" unless operation

    ActiveRecord::Base.connection_pool.with_connection do |connection|
      if connection.transaction_open?
        raise ArgumentError,
          "MobilityTransaction must start outside any existing transaction"
      end

      attempts = 0
      begin
        attempts += 1
        connection.transaction(isolation: :serializable) do
          operation.call
        end
      rescue ActiveRecord::SerializationFailure, ActiveRecord::Deadlocked
        raise if attempts >= max_attempts

        # Retry the complete transaction after rollback with bounded jitter.
        sleep([0.025 * (2**(attempts - 1)), 0.4].min + rand * 0.025)
        retry
      end
    end
  end
end
