module Staff
  class BaseController < ApplicationController
    layout "operations"
    before_action :require_login
    before_action :require_staff
    private
    def require_staff
      head :forbidden unless %w[inventory.read intake.review distribution.manage shifts.manage content.manage reports.read users.manage].any? { |permission| allowed?(permission) }
    end
  end
end
