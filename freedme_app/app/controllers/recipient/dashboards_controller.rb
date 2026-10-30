module Recipient
  class DashboardsController < AuthenticatedController
    def show
      redirect_to activity_path
    end
  end
end
