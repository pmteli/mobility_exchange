class MoneyDonation < MobilityRecord
  self.table_name = "mobility_exchange.money_donations"
  belongs_to :user
  PRESETS = [10, 25, 50, 100, 500].freeze
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 100, less_than_or_equal_to: 1_000_000 }

  def self.parse_amount(choice, custom)
    value = choice == "custom" ? custom.to_s.strip : choice.to_s
    unless (choice == "custom" || PRESETS.map(&:to_s).include?(choice)) && value.match?(/\A\d{1,5}(\.\d{1,2})?\z/)
      raise Workflow::Error, "Choose a donation amount or enter a custom amount with up to two decimal places."
    end
    cents = (BigDecimal(value) * 100).to_i
    raise Workflow::Error, "Enter an amount between $1.00 and $10,000.00 USD." unless (100..1_000_000).cover?(cents)
    cents
  end
end
