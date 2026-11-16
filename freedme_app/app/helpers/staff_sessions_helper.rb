module StaffSessionsHelper
  # FR003 / NFR003: generate locally; never send the enrollment secret to a QR service.
  def staff_enrollment_qr(credential)
    return if credential.mfa_enrolled_at

    uri = Staff::Authentication.totp(credential).provisioning_uri(credential.username)
    RQRCode::QRCode.new(uri).as_svg(
      module_size: 5, offset: 20, fill: 'ffffff', color: '000000',
      use_path: true, viewbox: true,
      svg_attributes: { role: 'img', 'aria-label' => 'Scan to set up your FreeDME Staff authenticator' }
    ).html_safe
  end
end
