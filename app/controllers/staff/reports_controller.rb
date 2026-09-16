require "csv"
module Staff
  class ReportsController < BaseController
    before_action -> { authorize!("reports.read") }
    def index
      @totals = Equipment.where(archived_at: nil).group(:status_code).count
      respond_to do |format|
        format.html
        format.csv do
          data = CSV.generate do |csv|
            csv << ["Status", "Units"]
            @totals.sort.each { |status, count| csv << [status, count] }
          end
          send_data data, filename: "inventory-totals-#{Date.current}.csv", type: "text/csv"
        end
      end
    end
  end
end
