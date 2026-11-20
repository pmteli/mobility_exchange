class MyAccountController < AuthenticatedController
  before_action :private_response
  before_action :require_member_mobile, except: :show
  def show
    @contact = mobile_contact
    @mobile = @contact && Journeys::Support.decrypt(@contact.value_ciphertext)
    @sms_enabled = @contact && Integrations::SmsConsent.allowed?(@contact.lookup_hmac, account_id: @contact.account_id)
  end

  def mobile
    @verified = session[:mobile_change_verified_until].to_i > Time.current.to_i
  end

  def start_current_verification
    session.delete(:mobile_change_verified_until)
    session.delete(:mobile_change_new)
    session[:mobile_change_current] = Journeys::Authentication.start!(mobile: Journeys::Support.decrypt(mobile_contact.value_ciphertext))
    redirect_to account_mobile_path
  rescue Journeys::Error => e
    redirect_to account_mobile_path, alert: e.message
  end

  def verify_current
    pending = session[:mobile_change_current]
    raise Journeys::Error, 'Request a new code for your current mobile number.' unless pending
    challenge = AuthChallenge.find(pending.fetch('challenge_id'))
    raise Journeys::Error, 'This verification does not belong to your account.' unless challenge.account_id == current_account.id
    Journeys::Authentication.verify!(pending, params[:code].to_s)
    session.delete(:mobile_change_current)
    session[:mobile_change_contact_id] = mobile_contact.id
    session[:mobile_change_verified_until] = 10.minutes.from_now.to_i
    redirect_to account_mobile_path, notice: 'Current mobile verified. Enter your new mobile number.'
  rescue Journeys::Error, ActiveRecord::RecordNotFound => e
    redirect_to account_mobile_path, alert: e.is_a?(Journeys::Error) ? e.message : 'Request a new verification code.'
  end

  def send_new_code
    require_recent_verification!
    session[:mobile_change_new] = Journeys::MobileChange.start!(current_account, params[:mobile])
    redirect_to account_mobile_path, notice: 'A verification code was sent to your new number.'
  rescue Journeys::Error => e
    redirect_to account_mobile_path, alert: e.message
  end

  def confirm_mobile
    require_recent_verification!
    Journeys::MobileChange.confirm!(current_account, session[:mobile_change_contact_id], session[:mobile_change_new], params[:code].to_s)
    id = current_account.id
    reset_session
    session[:account_id] = id
    session[:expires_at] = 8.hours.from_now.to_i
    redirect_to my_account_path, notice: 'Mobile number updated. Optional SMS notifications are off; review your SMS preferences below.'
  rescue Journeys::Error => e
    redirect_to account_mobile_path, alert: e.message
  end

  def cancel_mobile
    %i[mobile_change_current mobile_change_new mobile_change_verified_until mobile_change_contact_id].each { |k| session.delete(k) }
    redirect_to my_account_path
  end

  private
  def require_member_mobile
    redirect_to my_account_path, alert: 'Staff use email, password and authenticator sign-in.' if Staff::Authentication.staff?(current_account) || !mobile_contact
  end
  def mobile_contact
    AccountContact.find_by(account_id: current_account.id, kind: 'mobile', revoked_at: nil)
  end
  def private_response
    response.headers['Cache-Control'] = 'no-store'
  end
  def require_recent_verification!
    unless session[:mobile_change_verified_until].to_i > Time.current.to_i && session[:mobile_change_contact_id] == mobile_contact.id
      raise Journeys::Error, 'Verify your current mobile number again before changing it.'
    end
  end
end
