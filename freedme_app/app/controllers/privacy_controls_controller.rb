class PrivacyControlsController < AuthenticatedController
  before_action :require_administrator, only: [:review, :review_account, :operations, :create_backup]

  def show
    @deletion_request = PrivacyDeletionRequest.find_by(account_id: current_account.id)
  end

  def request_deletion
    unless params[:confirmed] == '1'
      redirect_to privacy_controls_path, alert: 'Confirm that you want to request permanent deletion.'
      return
    end
    PrivacyDeletionRequest.create_or_find_by!(account_id: current_account.id)
    redirect_to privacy_controls_path, notice: 'Your deletion request is awaiting administrator review. Your data has not yet been deleted.'
  end

  def create_backup
    Privacy::ManagedBackup.create!
    redirect_to activity_path(anchor: 'backup-recovery'), notice: 'Encrypted database backup created successfully.'
  rescue Privacy::ManagedBackup::Error, SystemCallError
    redirect_to activity_path(anchor: 'backup-recovery'), alert: 'Backup could not be created. Ask the system operator to check backup configuration and database connectivity.'
  end

  def operations
    response.headers['Cache-Control'] = 'no-store'
    @operations_guide = Rails.root.join('docs/PRIVACY_OPERATIONS.txt').read
  end

  def review
    @requests = PrivacyDeletionRequest.includes(:account).order(:requested_at)
    @inactive = Account.where(status: 'active').where('COALESCE(last_activity_at, created_at) <= ?', 3.months.ago)
      .where('last_inactivity_reviewed_at IS NULL OR last_inactivity_reviewed_at <= ?', 3.months.ago)
      .order(:created_at)
  end

  def review_account
    account = Account.find(params[:id])
    account.update!(last_inactivity_reviewed_at: Time.current)
    redirect_to privacy_review_path, notice: 'Account review recorded. No account data was deleted.'
  end

  private
  def require_administrator
    head :forbidden unless AccountRole.exists?(account_id: current_account.id, role: 'administrator')
  end
end
