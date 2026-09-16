module ScheduleValidations
  extend ActiveSupport::Concern
  included do
    validates :location_id, :starts_at, :ends_at, presence: true
    validates :capacity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1000 }
    validate :end_follows_start
    validate :start_is_future, on: :create
  end
  private
  def end_follows_start
    errors.add(:ends_at, "must be after the start") if starts_at && ends_at && ends_at <= starts_at
  end
  def start_is_future
    errors.add(:starts_at, "must be in the future") if starts_at && starts_at <= Time.current
  end
end
