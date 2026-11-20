class Staff::NotificationMobilesController < AuthenticatedController
  before_action :require_staff
  rate_limit to: 10, within: 10.minutes, only: [:create, :confirm]
  def new; end
  def create
    session[:staff_notification_mobile] = Journeys::MobileChange.start!(current_account, params[:mobile])
    redirect_to staff_notification_mobile_path, notice: 'Enter the code sent to your notification number.'
  rescue Journeys::Error => e
    redirect_to staff_notification_mobile_path, alert: e.message
  end
  def confirm
    Journeys::MobileChange.confirm!(current_account, nil, session[:staff_notification_mobile], params[:code].to_s, staff_enrollment: true)
    session.delete(:staff_notification_mobile)
    redirect_to my_account_path(anchor: 'sms-preferences'), notice: 'Notification number verified. Enable SMS Preferences below to receive moderator alerts.'
  rescue Journeys::Error => e
    redirect_to staff_notification_mobile_path, alert: e.message
  end
  private
  def require_staff
    unless Staff::Authentication.staff?(current_account)
      head :forbidden
      return
    end
    if AccountContact.exists?(account_id: current_account.id, kind: 'mobile', revoked_at: nil)
      redirect_to my_account_path, alert: 'A mobile number is already configured. Contact the administrator to change a staff notification number.'
    end
  end
end
