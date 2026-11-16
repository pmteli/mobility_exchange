class SmsPreferencesController < AuthenticatedController
  def update
    contact = AccountContact.find_by(account_id: current_account.id, kind: "mobile", revoked_at: nil)
    return redirect_to my_account_path, alert: 'No mobile number is associated with this account.' unless contact
    if params[:sms_consent] == "1" && Integrations::SmsConsent.carrier_stopped?(contact)
      return redirect_to my_account_path(anchor: "sms-preferences"), alert: "You previously replied STOP. Contact support to restore SMS preferences; enabling this checkbox does not clear the carrier block."
    end
    ConsentEvent.create!(account_id: current_account.id, contact_id: contact.id, purpose: "routine_sms",
      action: params[:sms_consent] == "1" ? "granted" : "withdrawn", idempotency_key: SecureRandom.uuid)
    redirect_to my_account_path(anchor: "sms-preferences"), notice: "SMS preference saved."
  end
end
