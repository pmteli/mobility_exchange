module Staff
  class DashboardController < BaseController
    def index
      @totals = allowed?("inventory.read") ? Equipment.where(archived_at: nil).group(:status_code).count : {}
    end
  end
end
