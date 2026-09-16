class SignDocument
  CONSENT = "I have read the complete document shown here and agree to sign it electronically.".freeze
  def self.call(actor, record, version_id, signature, consent)
    raise Workflow::Error, "Enter your full name and confirm consent." unless signature.to_s.strip.length.between?(2, 150) && consent == "1"
    kind = record.is_a?(EquipmentRequest) ? "recipient_waiver" : "donor_certification"
    field = kind == "recipient_waiver" ? :requested_by : :submitted_by
    Workflow.owner!(actor, record, field)
    version = LegalDocumentVersion.find(version_id)
    raise Workflow::Error, "The document is no longer current. Reload the page." unless ActiveLegalDocument.exists?(kind: kind, version_id: version.id)
    signed_at = Time.current
    evidence = { signer: signature.strip, user_id: actor.id, record_id: record.id, version_id: version.id, text_sha256: version.text_sha256, signed_at: signed_at.iso8601(6), consent: CONSENT }
    json = PrivateEvidence.prepare(JSON.generate(evidence), "signature.json", "application/json")
    pdf = Prawn::Document.new
    font = ENV.fetch("PDF_FONT", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")
    raise Workflow::Error, "PDF font is not configured. Set PDF_FONT to a Unicode TrueType font." unless File.file?(font)
    pdf.font(font)
    pdf.text(version.title, size: 18)
    pdf.move_down(12)
    pdf.text(version.exact_text)
    pdf.move_down(20)
    pdf.text("Signed by #{signature.strip} at #{signed_at.iso8601}
#{CONSENT}
Document SHA256: #{version.text_sha256}")
    document = PrivateEvidence.prepare(pdf.render, "signed-document.pdf", "application/pdf")
    Workflow.run do
      record.reload
      Workflow.owner!(actor, record, field)
      raise Workflow::Error, "This submission can no longer be signed." if %w[rejected cancelled completed].include?(record.status)
      raise Workflow::Error, "The document changed. Reload and review it again." unless ActiveLegalDocument.exists?(kind: kind, version_id: version.id)
      attrs = { version_id: version.id, signer_name: signature.strip, signature_evidence_file_id: PrivateEvidence.persist!(json, actor).id, signed_pdf_file_id: PrivateEvidence.persist!(document, actor).id, signed_at: signed_at, consent_text: CONSENT }
      signed = if kind == "recipient_waiver"
        SignedWaiver.create!(attrs.merge(recipient_id: record.recipient_id, request_id: record.id, signer_capacity: "self", signature_method: "typed", metadata_json: evidence))
      else
        SignedDonorCertification.create!(attrs.merge(intake_id: record.id))
      end
      Audit.record!(actor, "document.signed", signed)
      signed
    end
  end
end
