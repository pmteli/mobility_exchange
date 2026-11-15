class ReportingArchive < ApplicationRecord
  self.table_name = 'freedme.reporting_archives'
  belongs_to :exchange, optional: true
  belongs_to :listing
end
