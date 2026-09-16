SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: mobility_exchange; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA mobility_exchange;


--
-- Name: fn_active_document_kind_insert(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_active_document_kind_insert() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NOT EXISTS(SELECT 1 FROM legal_document_versions WHERE id=NEW.version_id AND kind=NEW.kind) THEN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document kind mismatch';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_active_document_kind_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_active_document_kind_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NOT EXISTS(SELECT 1 FROM legal_document_versions WHERE id=NEW.version_id AND kind=NEW.kind) THEN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document kind mismatch';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_appointment_validate_insert(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_appointment_validate_insert() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.status='booked' THEN
IF NOT EXISTS(SELECT 1 FROM appointment_slots WHERE id=NEW.slot_id AND cancelled_at IS NULL AND ((kind='pickup' AND NEW.request_id IS NOT NULL) OR (kind='dropoff' AND NEW.intake_id IS NOT NULL))) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Compatible active appointment slot required';
END IF;
 IF (SELECT count(*) FROM appointments WHERE slot_id=NEW.slot_id AND status='booked' AND id<>NEW.id)>=(SELECT capacity FROM appointment_slots WHERE id=NEW.slot_id) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Appointment slot is full';
END IF;
 IF EXISTS(SELECT 1 FROM appointment_slots s JOIN location_closures c ON c.location_id=s.location_id WHERE s.id=NEW.slot_id AND c.starts_at<s.ends_at AND c.ends_at>s.starts_at) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Location is closed';
END IF;
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_appointment_validate_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_appointment_validate_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.status='booked' THEN
IF NOT EXISTS(SELECT 1 FROM appointment_slots WHERE id=NEW.slot_id AND cancelled_at IS NULL AND ((kind='pickup' AND NEW.request_id IS NOT NULL) OR (kind='dropoff' AND NEW.intake_id IS NOT NULL))) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Compatible active appointment slot required';
END IF;
 IF (SELECT count(*) FROM appointments WHERE slot_id=NEW.slot_id AND status='booked' AND id<>NEW.id)>=(SELECT capacity FROM appointment_slots WHERE id=NEW.slot_id) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Appointment slot is full';
END IF;
 IF EXISTS(SELECT 1 FROM appointment_slots s JOIN location_closures c ON c.location_id=s.location_id WHERE s.id=NEW.slot_id AND c.starts_at<s.ends_at AND c.ends_at>s.starts_at) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Location is closed';
END IF;
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_audit_events_no_delete(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_audit_events_no_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN OLD;
END;
$$;


--
-- Name: fn_audit_events_no_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_audit_events_no_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN NEW;
END;
$$;


--
-- Name: fn_certification_document_kind(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_certification_document_kind() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NOT EXISTS(SELECT 1 FROM legal_document_versions WHERE id=NEW.version_id AND kind='donor_certification') THEN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Donor certification version required';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_distribution_complete(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_distribution_complete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
UPDATE equipment SET status_code='distributed',updated_by=NEW.released_by,updated_at=NEW.released_at WHERE id=NEW.equipment_id;
 UPDATE reservations SET status='fulfilled',closed_by=NEW.released_by WHERE id=NEW.reservation_id;
 UPDATE equipment_requests SET status='completed' WHERE id=NEW.request_id AND NOT EXISTS(SELECT 1 FROM request_items ri WHERE ri.request_id=NEW.request_id AND NOT EXISTS(SELECT 1 FROM distributions d WHERE d.request_id=ri.request_id AND d.equipment_id=ri.equipment_id));
 UPDATE appointments SET status='completed' WHERE id=NEW.appointment_id AND EXISTS(SELECT 1 FROM equipment_requests WHERE id=NEW.request_id AND status='completed');
RETURN NEW;
END;
$$;


--
-- Name: fn_distribution_validate(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_distribution_validate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NOT EXISTS(SELECT 1 FROM reservations WHERE id=NEW.reservation_id AND status='active') THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Active reservation required';
END IF;
 IF NOT EXISTS(SELECT 1 FROM appointments WHERE id=NEW.appointment_id AND status='booked') THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Booked pickup required';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_distributions_clean_files(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_distributions_clean_files() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NOT EXISTS(SELECT 1 FROM files WHERE id=NEW.pickup_signature_file_id AND scan_status='clean' AND deleted_at IS NULL) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean stored evidence required';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_distributions_no_delete(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_distributions_no_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN OLD;
END;
$$;


--
-- Name: fn_distributions_no_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_distributions_no_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN NEW;
END;
$$;


--
-- Name: fn_equipment_history_insert(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_equipment_history_insert() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
INSERT INTO equipment_status_history(equipment_id,to_status,actor_id) VALUES(NEW.id,NEW.status_code,NEW.created_by);
RETURN NEW;
END;
$$;


--
-- Name: fn_equipment_history_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_equipment_history_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.status_code<>OLD.status_code THEN
INSERT INTO equipment_status_history(equipment_id,from_status,to_status,actor_id) VALUES(NEW.id,OLD.status_code,NEW.status_code,NEW.updated_by);
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_equipment_initial_status(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_equipment_initial_status() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.status_code<>'received' THEN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'New equipment must begin as received';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_equipment_status_history_no_delete(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_equipment_status_history_no_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN OLD;
END;
$$;


--
-- Name: fn_equipment_status_history_no_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_equipment_status_history_no_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN NEW;
END;
$$;


--
-- Name: fn_equipment_transition(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_equipment_transition() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.status_code<>OLD.status_code THEN
IF NOT EXISTS(SELECT 1 FROM inventory_transitions WHERE from_status=OLD.status_code AND to_status=NEW.status_code) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Invalid equipment transition';
END IF;
 IF NEW.status_code='reserved' AND NOT EXISTS(SELECT 1 FROM reservations WHERE equipment_id=NEW.id AND status='active') THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Active reservation required';
END IF;
 IF NEW.status_code='distributed' AND NOT EXISTS(SELECT 1 FROM distributions WHERE equipment_id=NEW.id) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Distribution transaction required';
END IF;
 IF OLD.status_code='reserved' AND NEW.status_code='available' AND EXISTS(SELECT 1 FROM reservations WHERE equipment_id=NEW.id AND status='active') THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Close reservation first';
END IF;
 IF NEW.status_code='available' AND OLD.status_code<>'reserved' AND (NOT EXISTS(SELECT 1 FROM processing_events WHERE equipment_id=NEW.id AND kind='inspection' AND outcome='passed') OR NOT EXISTS(SELECT 1 FROM processing_events WHERE equipment_id=NEW.id AND kind='sanitization' AND outcome='completed')) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Inspection and sanitization evidence required';
END IF;
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_files_signed_no_delete(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_files_signed_no_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF EXISTS(SELECT 1 FROM signed_waivers WHERE signature_evidence_file_id=OLD.id OR signed_pdf_file_id=OLD.id) OR EXISTS(SELECT 1 FROM signed_donor_certifications WHERE signature_evidence_file_id=OLD.id OR signed_pdf_file_id=OLD.id) OR EXISTS(SELECT 1 FROM distributions WHERE pickup_signature_file_id=OLD.id) THEN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Signed file metadata is immutable';
END IF;
RETURN OLD;
END;
$$;


--
-- Name: fn_files_signed_no_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_files_signed_no_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF EXISTS(SELECT 1 FROM signed_waivers WHERE signature_evidence_file_id=OLD.id OR signed_pdf_file_id=OLD.id) OR EXISTS(SELECT 1 FROM signed_donor_certifications WHERE signature_evidence_file_id=OLD.id OR signed_pdf_file_id=OLD.id) OR EXISTS(SELECT 1 FROM distributions WHERE pickup_signature_file_id=OLD.id) THEN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Signed file metadata is immutable';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_legal_document_versions_no_delete(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_legal_document_versions_no_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN OLD;
END;
$$;


--
-- Name: fn_legal_document_versions_no_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_legal_document_versions_no_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN NEW;
END;
$$;


--
-- Name: fn_processing_events_no_delete(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_processing_events_no_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN OLD;
END;
$$;


--
-- Name: fn_processing_events_no_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_processing_events_no_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN NEW;
END;
$$;


--
-- Name: fn_reservation_activate(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_reservation_activate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
UPDATE equipment SET status_code='reserved',updated_by=NEW.reserved_by,updated_at=CURRENT_TIMESTAMP WHERE id=NEW.equipment_id;
RETURN NEW;
END;
$$;


--
-- Name: fn_reservation_finish(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_reservation_finish() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.status<>OLD.status THEN
IF NEW.closed_by IS NULL THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Closing actor required';
END IF;
 IF OLD.status<>'active' THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Closed reservations cannot reopen';
END IF;
 IF NEW.status='fulfilled' AND NOT EXISTS(SELECT 1 FROM distributions WHERE reservation_id=NEW.id) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Distribution required';
END IF;
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_reservation_identity(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_reservation_identity() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.id<>OLD.id OR NEW.request_item_id<>OLD.request_item_id OR NEW.request_id<>OLD.request_id OR NEW.equipment_id<>OLD.equipment_id OR NEW.recipient_id<>OLD.recipient_id OR NEW.reserved_by<>OLD.reserved_by THEN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Reservation identity is immutable';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_reservation_no_delete(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_reservation_no_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Retain reservation history; cancel instead';
RETURN OLD;
END;
$$;


--
-- Name: fn_reservation_release(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_reservation_release() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF OLD.status='active' AND NEW.status IN ('cancelled','expired') THEN
UPDATE equipment SET status_code='available',updated_by=NEW.closed_by,updated_at=CURRENT_TIMESTAMP WHERE id=NEW.equipment_id;
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_reservation_validate(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_reservation_validate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.status<>'active' OR NOT EXISTS(SELECT 1 FROM equipment WHERE id=NEW.equipment_id AND status_code='available' AND archived_at IS NULL) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Equipment is not available';
END IF;
 IF NOT EXISTS(SELECT 1 FROM equipment_requests WHERE id=NEW.request_id AND status='approved') THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Approved request required';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_shift_cancel_signups(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_shift_cancel_signups() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF OLD.cancelled_at IS NULL AND NEW.cancelled_at IS NOT NULL THEN
UPDATE shift_signups SET status='cancelled' WHERE shift_id=NEW.id AND status='signed_up';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_shift_preserve_signups(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_shift_preserve_signups() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.capacity<(SELECT count(*) FROM shift_signups WHERE shift_id=OLD.id AND status IN ('signed_up','attended')) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Capacity below existing signups';
END IF;
 IF EXISTS(SELECT 1 FROM shift_signups WHERE shift_id=OLD.id AND status='signed_up') AND (NEW.starts_at<>OLD.starts_at OR NEW.ends_at<>OLD.ends_at OR NEW.location_id<>OLD.location_id) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Resolve signups before rescheduling shift';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_signed_donor_certifications_clean_files(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_signed_donor_certifications_clean_files() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NOT EXISTS(SELECT 1 FROM files WHERE id=NEW.signature_evidence_file_id AND scan_status='clean' AND deleted_at IS NULL) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean stored evidence required';
END IF;
IF NOT EXISTS(SELECT 1 FROM files WHERE id=NEW.signed_pdf_file_id AND scan_status='clean' AND deleted_at IS NULL AND mime_type='application/pdf') THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean stored evidence required';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_signed_donor_certifications_no_delete(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_signed_donor_certifications_no_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN OLD;
END;
$$;


--
-- Name: fn_signed_donor_certifications_no_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_signed_donor_certifications_no_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN NEW;
END;
$$;


--
-- Name: fn_signed_waivers_clean_files(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_signed_waivers_clean_files() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NOT EXISTS(SELECT 1 FROM files WHERE id=NEW.signature_evidence_file_id AND scan_status='clean' AND deleted_at IS NULL) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean stored evidence required';
END IF;
IF NOT EXISTS(SELECT 1 FROM files WHERE id=NEW.signed_pdf_file_id AND scan_status='clean' AND deleted_at IS NULL AND mime_type='application/pdf') THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean stored evidence required';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_signed_waivers_no_delete(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_signed_waivers_no_delete() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN OLD;
END;
$$;


--
-- Name: fn_signed_waivers_no_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_signed_waivers_no_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
RETURN NEW;
END;
$$;


--
-- Name: fn_signup_validate_insert(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_signup_validate_insert() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.status='signed_up' THEN
IF NOT EXISTS(SELECT 1 FROM volunteers v JOIN users u ON u.id=v.user_id WHERE v.user_id=NEW.volunteer_id AND v.approval_status='approved' AND u.account_status='active') THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Approved active volunteer required';
END IF;
 IF NOT EXISTS(SELECT 1 FROM volunteer_shifts WHERE id=NEW.shift_id AND cancelled_at IS NULL) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Active shift required';
END IF;
 IF (SELECT count(*) FROM shift_signups WHERE shift_id=NEW.shift_id AND status IN ('signed_up','attended') AND volunteer_id<>NEW.volunteer_id)>=(SELECT capacity FROM volunteer_shifts WHERE id=NEW.shift_id) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Volunteer shift is full';
END IF;
 IF EXISTS(SELECT 1 FROM shift_signups su JOIN volunteer_shifts other ON other.id=su.shift_id JOIN volunteer_shifts target ON target.id=NEW.shift_id WHERE su.volunteer_id=NEW.volunteer_id AND su.shift_id<>NEW.shift_id AND su.status='signed_up' AND other.cancelled_at IS NULL AND other.starts_at<target.ends_at AND other.ends_at>target.starts_at) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Volunteer shift overlaps existing signup';
END IF;
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_signup_validate_update(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_signup_validate_update() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NEW.status='signed_up' THEN
IF NOT EXISTS(SELECT 1 FROM volunteers v JOIN users u ON u.id=v.user_id WHERE v.user_id=NEW.volunteer_id AND v.approval_status='approved' AND u.account_status='active') THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Approved active volunteer required';
END IF;
 IF NOT EXISTS(SELECT 1 FROM volunteer_shifts WHERE id=NEW.shift_id AND cancelled_at IS NULL) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Active shift required';
END IF;
 IF (SELECT count(*) FROM shift_signups WHERE shift_id=NEW.shift_id AND status IN ('signed_up','attended') AND volunteer_id<>NEW.volunteer_id)>=(SELECT capacity FROM volunteer_shifts WHERE id=NEW.shift_id) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Volunteer shift is full';
END IF;
 IF EXISTS(SELECT 1 FROM shift_signups su JOIN volunteer_shifts other ON other.id=su.shift_id JOIN volunteer_shifts target ON target.id=NEW.shift_id WHERE su.volunteer_id=NEW.volunteer_id AND su.shift_id<>NEW.shift_id AND su.status='signed_up' AND other.cancelled_at IS NULL AND other.starts_at<target.ends_at AND other.ends_at>target.starts_at) THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Volunteer shift overlaps existing signup';
END IF;
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_slot_preserve_bookings(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_slot_preserve_bookings() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF EXISTS(SELECT 1 FROM appointments WHERE slot_id=OLD.id AND status='booked') THEN
IF NEW.cancelled_at IS NOT NULL OR NEW.location_id<>OLD.location_id OR NEW.kind<>OLD.kind OR NEW.starts_at<>OLD.starts_at OR NEW.ends_at<>OLD.ends_at THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Resolve booked appointments before changing slot';
END IF;
 IF NEW.capacity<(SELECT count(*) FROM appointments WHERE slot_id=OLD.id AND status='booked') THEN
 RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Capacity below existing bookings';
END IF;
END IF;
RETURN NEW;
END;
$$;


--
-- Name: fn_waiver_document_kind(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.fn_waiver_document_kind() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
IF NOT EXISTS(SELECT 1 FROM legal_document_versions WHERE id=NEW.version_id AND kind='recipient_waiver') THEN
RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Recipient waiver version required';
END IF;
RETURN NEW;
END;
$$;


--
-- Name: reject_truncate(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.reject_truncate() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
 RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='TRUNCATE is not a supported application operation';
END;
$$;


--
-- Name: require_serializable_write(); Type: FUNCTION; Schema: mobility_exchange; Owner: -
--

CREATE FUNCTION mobility_exchange.require_serializable_write() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'mobility_exchange', 'pg_catalog'
    AS $$
BEGIN
 IF current_setting('transaction_isolation') <> 'serializable' THEN
  RAISE EXCEPTION USING ERRCODE='25001', MESSAGE='Use BEGIN ISOLATION LEVEL SERIALIZABLE for Mobility Exchange writes';
 END IF;
 RETURN NULL;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_legal_documents; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.active_legal_documents (
    kind text NOT NULL,
    version_id text NOT NULL,
    CONSTRAINT active_legal_documents_kind_check CHECK ((kind = ANY (ARRAY['recipient_waiver'::text, 'donor_certification'::text])))
);


--
-- Name: appointment_slots; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.appointment_slots (
    id text NOT NULL,
    location_id text NOT NULL,
    kind text NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    capacity integer NOT NULL,
    cancelled_at timestamp with time zone,
    created_by text NOT NULL,
    CONSTRAINT appointment_slots_capacity_check CHECK ((capacity > 0)),
    CONSTRAINT appointment_slots_check CHECK ((ends_at > starts_at)),
    CONSTRAINT appointment_slots_kind_check CHECK ((kind = ANY (ARRAY['dropoff'::text, 'pickup'::text])))
);


--
-- Name: appointments; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.appointments (
    id text NOT NULL,
    slot_id text NOT NULL,
    intake_id text,
    request_id text,
    status text DEFAULT 'booked'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT appointments_check CHECK (((intake_id IS NOT NULL) <> (request_id IS NOT NULL))),
    CONSTRAINT appointments_status_check CHECK ((status = ANY (ARRAY['booked'::text, 'completed'::text, 'cancelled'::text, 'no_show'::text])))
);


--
-- Name: audit_events; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.audit_events (
    id bigint NOT NULL,
    actor_user_id text,
    actor_kind text NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    action text NOT NULL,
    before_json jsonb,
    after_json jsonb,
    correlation_id text,
    occurred_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT audit_events_actor_kind_check CHECK ((actor_kind = ANY (ARRAY['user'::text, 'system'::text, 'visitor'::text]))),
    CONSTRAINT audit_events_check CHECK ((((actor_kind = 'user'::text) AND (actor_user_id IS NOT NULL)) OR ((actor_kind <> 'user'::text) AND (actor_user_id IS NULL))))
);


--
-- Name: audit_events_id_seq; Type: SEQUENCE; Schema: mobility_exchange; Owner: -
--

ALTER TABLE mobility_exchange.audit_events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME mobility_exchange.audit_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: content_pages; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.content_pages (
    id text NOT NULL,
    slug text NOT NULL,
    title text NOT NULL,
    body_markdown text NOT NULL,
    published_at timestamp with time zone,
    updated_by text NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: conversation_participants; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.conversation_participants (
    conversation_id text NOT NULL,
    user_id text NOT NULL,
    last_read_at timestamp with time zone
);


--
-- Name: conversations; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.conversations (
    id text NOT NULL,
    subject text NOT NULL,
    equipment_id text,
    visitor_name text,
    visitor_email text,
    status text DEFAULT 'open'::text NOT NULL,
    assigned_to text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT conversations_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text])))
);


--
-- Name: credentials; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.credentials (
    user_id text NOT NULL,
    password_digest text NOT NULL,
    mfa_secret text,
    last_otp_at bigint,
    token_nonce text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: distributions; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.distributions (
    id text NOT NULL,
    reservation_id text NOT NULL,
    equipment_id text NOT NULL,
    recipient_id text NOT NULL,
    request_id text NOT NULL,
    waiver_id text NOT NULL,
    appointment_id text NOT NULL,
    released_by text NOT NULL,
    released_at timestamp with time zone NOT NULL,
    pickup_signature_file_id text NOT NULL,
    condition_at_pickup text NOT NULL,
    notes text
);


--
-- Name: donors; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.donors (
    id text NOT NULL,
    user_id text,
    first_name text NOT NULL,
    last_name text NOT NULL,
    organization text,
    email text,
    phone text,
    address_line1 text,
    address_line2 text,
    city text,
    region text,
    postal_code text,
    preferred_contact text,
    private_notes text,
    archived_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT donors_preferred_contact_check CHECK ((preferred_contact = ANY (ARRAY['email'::text, 'phone'::text, 'none'::text])))
);


--
-- Name: equipment; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.equipment (
    id text NOT NULL,
    inventory_number text NOT NULL,
    type_id text NOT NULL,
    name text NOT NULL,
    manufacturer text,
    model text,
    serial_number text,
    description text,
    color text,
    condition text NOT NULL,
    height_cm double precision,
    length_cm double precision,
    width_cm double precision,
    weight_kg double precision,
    max_user_weight_kg double precision,
    acquisition_kind text NOT NULL,
    intake_item_id text,
    purchase_line_id text,
    status_code text DEFAULT 'received'::text NOT NULL,
    location_id text NOT NULL,
    storage_position text,
    assigned_volunteer_id text,
    received_at timestamp with time zone NOT NULL,
    public_notes text,
    private_notes text,
    disposition_reason text,
    created_by text NOT NULL,
    updated_by text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    archived_at timestamp with time zone,
    CONSTRAINT equipment_acquisition_kind_check CHECK ((acquisition_kind = ANY (ARRAY['donation'::text, 'purchase'::text, 'legacy'::text]))),
    CONSTRAINT equipment_check CHECK ((((acquisition_kind = 'donation'::text) AND (intake_item_id IS NOT NULL) AND (purchase_line_id IS NULL)) OR ((acquisition_kind = 'purchase'::text) AND (purchase_line_id IS NOT NULL) AND (intake_item_id IS NULL)) OR ((acquisition_kind = 'legacy'::text) AND (intake_item_id IS NULL) AND (purchase_line_id IS NULL)))),
    CONSTRAINT equipment_check1 CHECK (((status_code <> 'disposal'::text) OR ((disposition_reason IS NOT NULL) AND (length(TRIM(BOTH FROM disposition_reason)) > 0)))),
    CONSTRAINT equipment_condition_check CHECK ((condition = ANY (ARRAY['new'::text, 'excellent'::text, 'good'::text, 'fair'::text, 'poor'::text, 'unknown'::text]))),
    CONSTRAINT equipment_height_cm_check CHECK ((height_cm > (0)::double precision)),
    CONSTRAINT equipment_length_cm_check CHECK ((length_cm > (0)::double precision)),
    CONSTRAINT equipment_max_user_weight_kg_check CHECK ((max_user_weight_kg > (0)::double precision)),
    CONSTRAINT equipment_weight_kg_check CHECK ((weight_kg > (0)::double precision)),
    CONSTRAINT equipment_width_cm_check CHECK ((width_cm > (0)::double precision))
);


--
-- Name: equipment_categories; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.equipment_categories (
    id text NOT NULL,
    name text NOT NULL,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: equipment_files; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.equipment_files (
    equipment_id text NOT NULL,
    file_id text NOT NULL,
    purpose text NOT NULL,
    public_approved boolean DEFAULT false NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    approved_by text,
    CONSTRAINT equipment_files_check CHECK (((public_approved = false) OR ((purpose = 'photo'::text) AND (approved_by IS NOT NULL)))),
    CONSTRAINT equipment_files_purpose_check CHECK ((purpose = ANY (ARRAY['photo'::text, 'manual'::text, 'inspection'::text, 'repair'::text, 'other'::text])))
);


--
-- Name: equipment_requests; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.equipment_requests (
    id text NOT NULL,
    reference_number text NOT NULL,
    recipient_id text NOT NULL,
    requested_by text,
    status text DEFAULT 'submitted'::text NOT NULL,
    submitted_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    rejection_reason text,
    private_notes text,
    archived_at timestamp with time zone,
    CONSTRAINT equipment_requests_status_check CHECK ((status = ANY (ARRAY['submitted'::text, 'under_review'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text, 'completed'::text])))
);


--
-- Name: equipment_status_history; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.equipment_status_history (
    id bigint NOT NULL,
    equipment_id text NOT NULL,
    from_status text,
    to_status text NOT NULL,
    actor_id text NOT NULL,
    changed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: equipment_status_history_id_seq; Type: SEQUENCE; Schema: mobility_exchange; Owner: -
--

ALTER TABLE mobility_exchange.equipment_status_history ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME mobility_exchange.equipment_status_history_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: equipment_types; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.equipment_types (
    id text NOT NULL,
    category_id text NOT NULL,
    name text NOT NULL,
    active boolean DEFAULT true NOT NULL
);


--
-- Name: files; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.files (
    id text NOT NULL,
    object_key text NOT NULL,
    original_filename text NOT NULL,
    mime_type text NOT NULL,
    byte_size bigint NOT NULL,
    sha256 text NOT NULL,
    uploaded_by text,
    scan_status text DEFAULT 'pending'::text NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT files_byte_size_check CHECK ((byte_size >= 0)),
    CONSTRAINT files_scan_status_check CHECK ((scan_status = ANY (ARRAY['pending'::text, 'clean'::text, 'rejected'::text]))),
    CONSTRAINT files_sha256_check CHECK ((length(sha256) = 64))
);


--
-- Name: intake_item_files; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.intake_item_files (
    intake_item_id text NOT NULL,
    file_id text NOT NULL,
    purpose text NOT NULL,
    CONSTRAINT intake_item_files_purpose_check CHECK ((purpose = ANY (ARRAY['front'::text, 'back'::text, 'side'::text, 'serial'::text, 'damage'::text, 'accessory'::text, 'other'::text])))
);


--
-- Name: intake_items; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.intake_items (
    id text NOT NULL,
    intake_id text NOT NULL,
    type_id text NOT NULL,
    name text NOT NULL,
    manufacturer text,
    model text,
    serial_number text,
    description text,
    condition text NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    approximate_age_years double precision,
    height_cm double precision,
    length_cm double precision,
    width_cm double precision,
    weight_kg double precision,
    notes text,
    CONSTRAINT intake_items_approximate_age_years_check CHECK ((approximate_age_years >= (0)::double precision)),
    CONSTRAINT intake_items_condition_check CHECK ((condition = ANY (ARRAY['new'::text, 'excellent'::text, 'good'::text, 'fair'::text, 'poor'::text, 'unknown'::text]))),
    CONSTRAINT intake_items_height_cm_check CHECK ((height_cm > (0)::double precision)),
    CONSTRAINT intake_items_length_cm_check CHECK ((length_cm > (0)::double precision)),
    CONSTRAINT intake_items_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT intake_items_weight_kg_check CHECK ((weight_kg > (0)::double precision)),
    CONSTRAINT intake_items_width_cm_check CHECK ((width_cm > (0)::double precision))
);


--
-- Name: intake_submissions; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.intake_submissions (
    id text NOT NULL,
    reference_number text NOT NULL,
    donor_id text NOT NULL,
    submitted_by text,
    status text DEFAULT 'draft'::text NOT NULL,
    preferred_location_id text,
    submitted_at timestamp with time zone,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    rejection_reason text,
    private_notes text,
    archived_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT intake_submissions_check CHECK (((status <> 'rejected'::text) OR ((length(TRIM(BOTH FROM rejection_reason)) > 0) AND (rejection_reason IS NOT NULL)))),
    CONSTRAINT intake_submissions_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'submitted'::text, 'under_review'::text, 'approved'::text, 'scheduled'::text, 'received'::text, 'completed'::text, 'rejected'::text, 'cancelled'::text])))
);


--
-- Name: inventory_status_totals; Type: VIEW; Schema: mobility_exchange; Owner: -
--

CREATE VIEW mobility_exchange.inventory_status_totals AS
 SELECT status_code,
    location_id,
    count(*) AS item_count
   FROM mobility_exchange.equipment
  WHERE (archived_at IS NULL)
  GROUP BY status_code, location_id;


--
-- Name: inventory_statuses; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.inventory_statuses (
    code text NOT NULL,
    label text NOT NULL,
    sort_order integer NOT NULL,
    system_managed boolean DEFAULT false NOT NULL
);


--
-- Name: inventory_transitions; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.inventory_transitions (
    from_status text NOT NULL,
    to_status text NOT NULL,
    CONSTRAINT inventory_transitions_check CHECK ((from_status <> to_status))
);


--
-- Name: legal_document_versions; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.legal_document_versions (
    id text NOT NULL,
    kind text NOT NULL,
    version text NOT NULL,
    title text NOT NULL,
    exact_text text NOT NULL,
    text_sha256 text NOT NULL,
    published_at timestamp with time zone NOT NULL,
    published_by text NOT NULL,
    CONSTRAINT legal_document_versions_kind_check CHECK ((kind = ANY (ARRAY['recipient_waiver'::text, 'donor_certification'::text]))),
    CONSTRAINT legal_document_versions_text_sha256_check CHECK ((length(text_sha256) = 64))
);


--
-- Name: location_closures; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.location_closures (
    id text NOT NULL,
    location_id text NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    reason text NOT NULL,
    CONSTRAINT location_closures_check CHECK ((ends_at > starts_at))
);


--
-- Name: location_hours; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.location_hours (
    id text NOT NULL,
    location_id text NOT NULL,
    weekday integer NOT NULL,
    opens_local time without time zone NOT NULL,
    closes_local time without time zone NOT NULL,
    CONSTRAINT location_hours_check CHECK ((opens_local < closes_local)),
    CONSTRAINT location_hours_weekday_check CHECK (((weekday >= 0) AND (weekday <= 6)))
);


--
-- Name: locations; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.locations (
    id text NOT NULL,
    name text NOT NULL,
    address_line1 text,
    address_line2 text,
    city text,
    region text,
    postal_code text,
    country_code text DEFAULT 'US'::text NOT NULL,
    timezone text DEFAULT 'America/Los_Angeles'::text NOT NULL,
    latitude double precision,
    longitude double precision,
    phone text,
    email text,
    instructions text,
    pickup_enabled boolean DEFAULT false NOT NULL,
    dropoff_enabled boolean DEFAULT false NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    CONSTRAINT locations_latitude_check CHECK (((latitude >= ('-90'::integer)::double precision) AND (latitude <= (90)::double precision))),
    CONSTRAINT locations_longitude_check CHECK (((longitude >= ('-180'::integer)::double precision) AND (longitude <= (180)::double precision))),
    CONSTRAINT locations_status_check CHECK ((status = ANY (ARRAY['active'::text, 'temporarily_unavailable'::text, 'archived'::text])))
);


--
-- Name: login_sessions; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.login_sessions (
    id text NOT NULL,
    user_id text NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: message_files; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.message_files (
    message_id text NOT NULL,
    file_id text NOT NULL
);


--
-- Name: messages; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.messages (
    id text NOT NULL,
    conversation_id text NOT NULL,
    sender_user_id text,
    sender_kind text NOT NULL,
    body text NOT NULL,
    sent_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT messages_check CHECK ((((sender_kind = 'user'::text) AND (sender_user_id IS NOT NULL)) OR ((sender_kind <> 'user'::text) AND (sender_user_id IS NULL)))),
    CONSTRAINT messages_sender_kind_check CHECK ((sender_kind = ANY (ARRAY['user'::text, 'visitor'::text, 'system'::text])))
);


--
-- Name: notification_outbox; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.notification_outbox (
    id text NOT NULL,
    deduplication_key text NOT NULL,
    recipient_user_id text,
    channel text NOT NULL,
    destination text NOT NULL,
    template_key text NOT NULL,
    payload_json jsonb NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    available_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    locked_at timestamp with time zone,
    sent_at timestamp with time zone,
    last_error text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT notification_outbox_attempts_check CHECK ((attempts >= 0)),
    CONSTRAINT notification_outbox_channel_check CHECK ((channel = ANY (ARRAY['email'::text, 'sms'::text, 'in_app'::text]))),
    CONSTRAINT notification_outbox_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'sent'::text, 'failed'::text, 'cancelled'::text])))
);


--
-- Name: organization_settings; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.organization_settings (
    key text NOT NULL,
    value_json jsonb NOT NULL,
    updated_by text NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: permissions; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.permissions (
    id text NOT NULL,
    description text NOT NULL
);


--
-- Name: processing_events; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.processing_events (
    id text NOT NULL,
    equipment_id text NOT NULL,
    kind text NOT NULL,
    outcome text NOT NULL,
    performed_by text NOT NULL,
    performed_at timestamp with time zone NOT NULL,
    notes text NOT NULL,
    checklist_json jsonb,
    supersedes_id text,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT processing_events_kind_check CHECK ((kind = ANY (ARRAY['inspection'::text, 'sanitization'::text, 'repair'::text, 'preparation'::text, 'disposal'::text]))),
    CONSTRAINT processing_events_outcome_check CHECK ((outcome = ANY (ARRAY['passed'::text, 'failed'::text, 'completed'::text, 'needs_repair'::text, 'not_suitable'::text])))
);


--
-- Name: public_available_equipment; Type: VIEW; Schema: mobility_exchange; Owner: -
--

CREATE VIEW mobility_exchange.public_available_equipment AS
 SELECT e.id,
    e.inventory_number,
    e.name,
    c.name AS category,
    t.name AS equipment_type,
    e.manufacturer,
    e.model,
    e.description,
    e.color,
    e.condition,
    e.height_cm,
    e.length_cm,
    e.width_cm,
    e.weight_kg,
    e.max_user_weight_kg,
    e.public_notes,
    l.name AS pickup_location
   FROM (((mobility_exchange.equipment e
     JOIN mobility_exchange.equipment_types t ON ((t.id = e.type_id)))
     JOIN mobility_exchange.equipment_categories c ON ((c.id = t.category_id)))
     JOIN mobility_exchange.locations l ON ((l.id = e.location_id)))
  WHERE ((e.status_code = 'available'::text) AND (e.archived_at IS NULL));


--
-- Name: public_equipment_photo_metadata; Type: VIEW; Schema: mobility_exchange; Owner: -
--

CREATE VIEW mobility_exchange.public_equipment_photo_metadata AS
 SELECT ef.equipment_id,
    ef.file_id,
    ef.sort_order
   FROM ((mobility_exchange.equipment_files ef
     JOIN mobility_exchange.files f ON ((f.id = ef.file_id)))
     JOIN mobility_exchange.public_available_equipment e ON ((e.id = ef.equipment_id)))
  WHERE ((ef.purpose = 'photo'::text) AND (ef.public_approved = true) AND (f.scan_status = 'clean'::text) AND (f.deleted_at IS NULL));


--
-- Name: purchase_lines; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.purchase_lines (
    id text NOT NULL,
    purchase_id text NOT NULL,
    type_id text NOT NULL,
    quantity integer NOT NULL,
    unit_cost_minor bigint NOT NULL,
    description text,
    CONSTRAINT purchase_lines_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT purchase_lines_unit_cost_minor_check CHECK ((unit_cost_minor >= 0))
);


--
-- Name: purchases; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.purchases (
    id text NOT NULL,
    vendor_name text NOT NULL,
    purchased_on date NOT NULL,
    currency text NOT NULL,
    funding_source text,
    receipt_file_id text,
    created_by text NOT NULL,
    notes text,
    CONSTRAINT purchases_currency_check CHECK ((length(currency) = 3))
);


--
-- Name: purchase_totals; Type: VIEW; Schema: mobility_exchange; Owner: -
--

CREATE VIEW mobility_exchange.purchase_totals AS
 SELECT p.id,
    p.currency,
    COALESCE(sum(((pl.quantity)::numeric * (pl.unit_cost_minor)::numeric)), (0)::numeric) AS total_cost_minor
   FROM (mobility_exchange.purchases p
     LEFT JOIN mobility_exchange.purchase_lines pl ON ((pl.purchase_id = p.id)))
  GROUP BY p.id, p.currency;


--
-- Name: recipients; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.recipients (
    id text NOT NULL,
    user_id text,
    first_name text NOT NULL,
    last_name text NOT NULL,
    email text,
    phone text,
    address_line1 text,
    address_line2 text,
    city text,
    region text,
    postal_code text,
    date_of_birth date,
    private_notes text,
    archived_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: record_holds; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.record_holds (
    id text NOT NULL,
    entity_type text NOT NULL,
    entity_id text NOT NULL,
    reason text NOT NULL,
    placed_by text NOT NULL,
    placed_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    released_by text,
    released_at timestamp with time zone
);


--
-- Name: request_items; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.request_items (
    id text NOT NULL,
    request_id text NOT NULL,
    equipment_id text NOT NULL
);


--
-- Name: reservations; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.reservations (
    id text NOT NULL,
    request_item_id text NOT NULL,
    request_id text NOT NULL,
    equipment_id text NOT NULL,
    recipient_id text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    reserved_by text NOT NULL,
    closed_by text,
    reserved_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    expires_at timestamp with time zone,
    CONSTRAINT reservations_status_check CHECK ((status = ANY (ARRAY['active'::text, 'fulfilled'::text, 'cancelled'::text, 'expired'::text])))
);


--
-- Name: role_permissions; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.role_permissions (
    role_id text NOT NULL,
    permission_id text NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.roles (
    id text NOT NULL,
    name text NOT NULL
);


--
-- Name: schema_versions; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.schema_versions (
    version integer NOT NULL,
    applied_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: shift_signups; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.shift_signups (
    shift_id text NOT NULL,
    volunteer_id text NOT NULL,
    status text DEFAULT 'signed_up'::text NOT NULL,
    signed_up_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    attendance_recorded_by text,
    attendance_recorded_at timestamp with time zone,
    CONSTRAINT shift_signups_status_check CHECK ((status = ANY (ARRAY['signed_up'::text, 'cancelled'::text, 'attended'::text, 'no_show'::text])))
);


--
-- Name: signed_donor_certifications; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.signed_donor_certifications (
    id text NOT NULL,
    intake_id text NOT NULL,
    version_id text NOT NULL,
    signer_name text NOT NULL,
    signature_evidence_file_id text NOT NULL,
    signed_pdf_file_id text NOT NULL,
    signed_at timestamp with time zone NOT NULL,
    consent_text text NOT NULL
);


--
-- Name: signed_waivers; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.signed_waivers (
    id text NOT NULL,
    recipient_id text NOT NULL,
    request_id text NOT NULL,
    version_id text NOT NULL,
    signer_name text NOT NULL,
    signer_capacity text NOT NULL,
    representative_authority text,
    signature_method text NOT NULL,
    signature_evidence_file_id text NOT NULL,
    signed_pdf_file_id text NOT NULL,
    signed_at timestamp with time zone NOT NULL,
    consent_text text NOT NULL,
    metadata_json jsonb,
    CONSTRAINT signed_waivers_check CHECK (((signer_capacity <> 'authorized_representative'::text) OR ((representative_authority IS NOT NULL) AND (length(TRIM(BOTH FROM representative_authority)) > 0)))),
    CONSTRAINT signed_waivers_signature_method_check CHECK ((signature_method = ANY (ARRAY['typed'::text, 'drawn'::text, 'external_provider'::text]))),
    CONSTRAINT signed_waivers_signer_capacity_check CHECK ((signer_capacity = ANY (ARRAY['self'::text, 'authorized_representative'::text])))
);


--
-- Name: user_permission_grants; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.user_permission_grants (
    user_id text NOT NULL,
    permission_id text NOT NULL,
    granted_by text NOT NULL,
    expires_at timestamp with time zone
);


--
-- Name: user_roles; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.user_roles (
    user_id text NOT NULL,
    role_id text NOT NULL,
    assigned_by text NOT NULL,
    assigned_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.users (
    id text NOT NULL,
    auth_subject text NOT NULL,
    email text NOT NULL,
    first_name text NOT NULL,
    last_name text NOT NULL,
    phone text,
    account_status text DEFAULT 'pending'::text NOT NULL,
    email_verified_at timestamp with time zone,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    archived_at timestamp with time zone,
    community_roles text[] DEFAULT '{}'::text[] NOT NULL,
    CONSTRAINT users_account_status_check CHECK ((account_status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'archived'::text]))),
    CONSTRAINT users_community_roles_allowed CHECK ((community_roles <@ ARRAY['volunteer'::text, 'donor'::text, 'recipient'::text]))
);


--
-- Name: volunteer_shifts; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.volunteer_shifts (
    id text NOT NULL,
    location_id text NOT NULL,
    activity text NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    capacity integer NOT NULL,
    created_by text NOT NULL,
    cancelled_at timestamp with time zone,
    notes text,
    CONSTRAINT volunteer_shifts_capacity_check CHECK ((capacity > 0)),
    CONSTRAINT volunteer_shifts_check CHECK ((ends_at > starts_at))
);


--
-- Name: volunteers; Type: TABLE; Schema: mobility_exchange; Owner: -
--

CREATE TABLE mobility_exchange.volunteers (
    user_id text NOT NULL,
    approval_status text DEFAULT 'pending'::text NOT NULL,
    approved_by text,
    approved_at timestamp with time zone,
    emergency_contact_name text,
    emergency_contact_phone text,
    skills text,
    private_notes text,
    CONSTRAINT volunteers_approval_status_check CHECK ((approval_status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'inactive'::text])))
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: active_legal_documents active_legal_documents_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.active_legal_documents
    ADD CONSTRAINT active_legal_documents_pkey PRIMARY KEY (kind);


--
-- Name: appointment_slots appointment_slots_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.appointment_slots
    ADD CONSTRAINT appointment_slots_pkey PRIMARY KEY (id);


--
-- Name: appointments appointments_id_request_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.appointments
    ADD CONSTRAINT appointments_id_request_id_key UNIQUE (id, request_id);


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (id);


--
-- Name: audit_events audit_events_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.audit_events
    ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);


--
-- Name: content_pages content_pages_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.content_pages
    ADD CONSTRAINT content_pages_pkey PRIMARY KEY (id);


--
-- Name: content_pages content_pages_slug_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.content_pages
    ADD CONSTRAINT content_pages_slug_key UNIQUE (slug);


--
-- Name: conversation_participants conversation_participants_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.conversation_participants
    ADD CONSTRAINT conversation_participants_pkey PRIMARY KEY (conversation_id, user_id);


--
-- Name: conversations conversations_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.conversations
    ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);


--
-- Name: credentials credentials_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.credentials
    ADD CONSTRAINT credentials_pkey PRIMARY KEY (user_id);


--
-- Name: distributions distributions_equipment_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.distributions
    ADD CONSTRAINT distributions_equipment_id_key UNIQUE (equipment_id);


--
-- Name: distributions distributions_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.distributions
    ADD CONSTRAINT distributions_pkey PRIMARY KEY (id);


--
-- Name: distributions distributions_reservation_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.distributions
    ADD CONSTRAINT distributions_reservation_id_key UNIQUE (reservation_id);


--
-- Name: donors donors_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.donors
    ADD CONSTRAINT donors_pkey PRIMARY KEY (id);


--
-- Name: donors donors_user_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.donors
    ADD CONSTRAINT donors_user_id_key UNIQUE (user_id);


--
-- Name: equipment_categories equipment_categories_name_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_categories
    ADD CONSTRAINT equipment_categories_name_key UNIQUE (name);


--
-- Name: equipment_categories equipment_categories_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_categories
    ADD CONSTRAINT equipment_categories_pkey PRIMARY KEY (id);


--
-- Name: equipment_files equipment_files_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_files
    ADD CONSTRAINT equipment_files_pkey PRIMARY KEY (equipment_id, file_id);


--
-- Name: equipment equipment_inventory_number_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment
    ADD CONSTRAINT equipment_inventory_number_key UNIQUE (inventory_number);


--
-- Name: equipment equipment_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment
    ADD CONSTRAINT equipment_pkey PRIMARY KEY (id);


--
-- Name: equipment_requests equipment_requests_id_recipient_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_requests
    ADD CONSTRAINT equipment_requests_id_recipient_id_key UNIQUE (id, recipient_id);


--
-- Name: equipment_requests equipment_requests_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_requests
    ADD CONSTRAINT equipment_requests_pkey PRIMARY KEY (id);


--
-- Name: equipment_requests equipment_requests_reference_number_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_requests
    ADD CONSTRAINT equipment_requests_reference_number_key UNIQUE (reference_number);


--
-- Name: equipment_status_history equipment_status_history_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_status_history
    ADD CONSTRAINT equipment_status_history_pkey PRIMARY KEY (id);


--
-- Name: equipment_types equipment_types_category_id_name_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_types
    ADD CONSTRAINT equipment_types_category_id_name_key UNIQUE (category_id, name);


--
-- Name: equipment_types equipment_types_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_types
    ADD CONSTRAINT equipment_types_pkey PRIMARY KEY (id);


--
-- Name: files files_object_key_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.files
    ADD CONSTRAINT files_object_key_key UNIQUE (object_key);


--
-- Name: files files_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.files
    ADD CONSTRAINT files_pkey PRIMARY KEY (id);


--
-- Name: intake_item_files intake_item_files_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_item_files
    ADD CONSTRAINT intake_item_files_pkey PRIMARY KEY (intake_item_id, file_id);


--
-- Name: intake_items intake_items_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_items
    ADD CONSTRAINT intake_items_pkey PRIMARY KEY (id);


--
-- Name: intake_submissions intake_submissions_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_submissions
    ADD CONSTRAINT intake_submissions_pkey PRIMARY KEY (id);


--
-- Name: intake_submissions intake_submissions_reference_number_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_submissions
    ADD CONSTRAINT intake_submissions_reference_number_key UNIQUE (reference_number);


--
-- Name: inventory_statuses inventory_statuses_label_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.inventory_statuses
    ADD CONSTRAINT inventory_statuses_label_key UNIQUE (label);


--
-- Name: inventory_statuses inventory_statuses_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.inventory_statuses
    ADD CONSTRAINT inventory_statuses_pkey PRIMARY KEY (code);


--
-- Name: inventory_transitions inventory_transitions_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.inventory_transitions
    ADD CONSTRAINT inventory_transitions_pkey PRIMARY KEY (from_status, to_status);


--
-- Name: legal_document_versions legal_document_versions_kind_version_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.legal_document_versions
    ADD CONSTRAINT legal_document_versions_kind_version_key UNIQUE (kind, version);


--
-- Name: legal_document_versions legal_document_versions_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.legal_document_versions
    ADD CONSTRAINT legal_document_versions_pkey PRIMARY KEY (id);


--
-- Name: location_closures location_closures_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.location_closures
    ADD CONSTRAINT location_closures_pkey PRIMARY KEY (id);


--
-- Name: location_hours location_hours_location_id_weekday_opens_local_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.location_hours
    ADD CONSTRAINT location_hours_location_id_weekday_opens_local_key UNIQUE (location_id, weekday, opens_local);


--
-- Name: location_hours location_hours_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.location_hours
    ADD CONSTRAINT location_hours_pkey PRIMARY KEY (id);


--
-- Name: locations locations_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.locations
    ADD CONSTRAINT locations_pkey PRIMARY KEY (id);


--
-- Name: login_sessions login_sessions_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.login_sessions
    ADD CONSTRAINT login_sessions_pkey PRIMARY KEY (id);


--
-- Name: message_files message_files_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.message_files
    ADD CONSTRAINT message_files_pkey PRIMARY KEY (message_id, file_id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: notification_outbox notification_outbox_deduplication_key_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.notification_outbox
    ADD CONSTRAINT notification_outbox_deduplication_key_key UNIQUE (deduplication_key);


--
-- Name: notification_outbox notification_outbox_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.notification_outbox
    ADD CONSTRAINT notification_outbox_pkey PRIMARY KEY (id);


--
-- Name: organization_settings organization_settings_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.organization_settings
    ADD CONSTRAINT organization_settings_pkey PRIMARY KEY (key);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: processing_events processing_events_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.processing_events
    ADD CONSTRAINT processing_events_pkey PRIMARY KEY (id);


--
-- Name: processing_events processing_events_supersedes_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.processing_events
    ADD CONSTRAINT processing_events_supersedes_id_key UNIQUE (supersedes_id);


--
-- Name: purchase_lines purchase_lines_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.purchase_lines
    ADD CONSTRAINT purchase_lines_pkey PRIMARY KEY (id);


--
-- Name: purchases purchases_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.purchases
    ADD CONSTRAINT purchases_pkey PRIMARY KEY (id);


--
-- Name: recipients recipients_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.recipients
    ADD CONSTRAINT recipients_pkey PRIMARY KEY (id);


--
-- Name: recipients recipients_user_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.recipients
    ADD CONSTRAINT recipients_user_id_key UNIQUE (user_id);


--
-- Name: record_holds record_holds_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.record_holds
    ADD CONSTRAINT record_holds_pkey PRIMARY KEY (id);


--
-- Name: request_items request_items_id_request_id_equipment_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.request_items
    ADD CONSTRAINT request_items_id_request_id_equipment_id_key UNIQUE (id, request_id, equipment_id);


--
-- Name: request_items request_items_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.request_items
    ADD CONSTRAINT request_items_pkey PRIMARY KEY (id);


--
-- Name: request_items request_items_request_id_equipment_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.request_items
    ADD CONSTRAINT request_items_request_id_equipment_id_key UNIQUE (request_id, equipment_id);


--
-- Name: reservations reservations_id_equipment_id_recipient_id_request_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.reservations
    ADD CONSTRAINT reservations_id_equipment_id_recipient_id_request_id_key UNIQUE (id, equipment_id, recipient_id, request_id);


--
-- Name: reservations reservations_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.reservations
    ADD CONSTRAINT reservations_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id);


--
-- Name: roles roles_name_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.roles
    ADD CONSTRAINT roles_name_key UNIQUE (name);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schema_versions schema_versions_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.schema_versions
    ADD CONSTRAINT schema_versions_pkey PRIMARY KEY (version);


--
-- Name: shift_signups shift_signups_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.shift_signups
    ADD CONSTRAINT shift_signups_pkey PRIMARY KEY (shift_id, volunteer_id);


--
-- Name: signed_donor_certifications signed_donor_certifications_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_donor_certifications
    ADD CONSTRAINT signed_donor_certifications_pkey PRIMARY KEY (id);


--
-- Name: signed_donor_certifications signed_donor_certifications_signed_pdf_file_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_donor_certifications
    ADD CONSTRAINT signed_donor_certifications_signed_pdf_file_id_key UNIQUE (signed_pdf_file_id);


--
-- Name: signed_waivers signed_waivers_id_recipient_id_request_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_waivers
    ADD CONSTRAINT signed_waivers_id_recipient_id_request_id_key UNIQUE (id, recipient_id, request_id);


--
-- Name: signed_waivers signed_waivers_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_waivers
    ADD CONSTRAINT signed_waivers_pkey PRIMARY KEY (id);


--
-- Name: signed_waivers signed_waivers_signed_pdf_file_id_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_waivers
    ADD CONSTRAINT signed_waivers_signed_pdf_file_id_key UNIQUE (signed_pdf_file_id);


--
-- Name: user_permission_grants user_permission_grants_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.user_permission_grants
    ADD CONSTRAINT user_permission_grants_pkey PRIMARY KEY (user_id, permission_id);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);


--
-- Name: users users_auth_subject_key; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.users
    ADD CONSTRAINT users_auth_subject_key UNIQUE (auth_subject);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: volunteer_shifts volunteer_shifts_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.volunteer_shifts
    ADD CONSTRAINT volunteer_shifts_pkey PRIMARY KEY (id);


--
-- Name: volunteers volunteers_pkey; Type: CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.volunteers
    ADD CONSTRAINT volunteers_pkey PRIMARY KEY (user_id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: idx_appointments_slot_status; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_appointments_slot_status ON mobility_exchange.appointments USING btree (slot_id, status);


--
-- Name: idx_audit_entity_date; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_audit_entity_date ON mobility_exchange.audit_events USING btree (entity_type, entity_id, occurred_at);


--
-- Name: idx_distributions_recipient_date; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_distributions_recipient_date ON mobility_exchange.distributions USING btree (recipient_id, released_at);


--
-- Name: idx_equipment_intake; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_equipment_intake ON mobility_exchange.equipment USING btree (intake_item_id);


--
-- Name: idx_equipment_status_location; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_equipment_status_location ON mobility_exchange.equipment USING btree (status_code, location_id) WHERE (archived_at IS NULL);


--
-- Name: idx_equipment_type; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_equipment_type ON mobility_exchange.equipment USING btree (type_id);


--
-- Name: idx_history_equipment_date; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_history_equipment_date ON mobility_exchange.equipment_status_history USING btree (equipment_id, changed_at);


--
-- Name: idx_intake_items_submission; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_intake_items_submission ON mobility_exchange.intake_items USING btree (intake_id);


--
-- Name: idx_intakes_donor_date; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_intakes_donor_date ON mobility_exchange.intake_submissions USING btree (donor_id, created_at);


--
-- Name: idx_intakes_review; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_intakes_review ON mobility_exchange.intake_submissions USING btree (status, submitted_at);


--
-- Name: idx_messages_conversation_date; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_messages_conversation_date ON mobility_exchange.messages USING btree (conversation_id, sent_at);


--
-- Name: idx_outbox_due; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_outbox_due ON mobility_exchange.notification_outbox USING btree (status, available_at);


--
-- Name: idx_processing_equipment_date; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_processing_equipment_date ON mobility_exchange.processing_events USING btree (equipment_id, performed_at);


--
-- Name: idx_requests_recipient_date; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_requests_recipient_date ON mobility_exchange.equipment_requests USING btree (recipient_id, submitted_at);


--
-- Name: idx_requests_review; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_requests_review ON mobility_exchange.equipment_requests USING btree (status, submitted_at);


--
-- Name: idx_reservations_request; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_reservations_request ON mobility_exchange.reservations USING btree (request_id, status);


--
-- Name: idx_shifts_location_date; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_shifts_location_date ON mobility_exchange.volunteer_shifts USING btree (location_id, starts_at);


--
-- Name: idx_signup_volunteer; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_signup_volunteer ON mobility_exchange.shift_signups USING btree (volunteer_id, status);


--
-- Name: idx_slots_location_date; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_slots_location_date ON mobility_exchange.appointment_slots USING btree (location_id, starts_at);


--
-- Name: idx_waivers_recipient_date; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX idx_waivers_recipient_date ON mobility_exchange.signed_waivers USING btree (recipient_id, signed_at);


--
-- Name: login_sessions_user_id_idx; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE INDEX login_sessions_user_id_idx ON mobility_exchange.login_sessions USING btree (user_id);


--
-- Name: uq_active_equipment_reservation; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE UNIQUE INDEX uq_active_equipment_reservation ON mobility_exchange.reservations USING btree (equipment_id) WHERE (status = 'active'::text);


--
-- Name: uq_active_intake_appointment; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE UNIQUE INDEX uq_active_intake_appointment ON mobility_exchange.appointments USING btree (intake_id) WHERE (status = 'booked'::text);


--
-- Name: uq_active_request_appointment; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE UNIQUE INDEX uq_active_request_appointment ON mobility_exchange.appointments USING btree (request_id) WHERE (status = 'booked'::text);


--
-- Name: uq_users_email_casefold; Type: INDEX; Schema: mobility_exchange; Owner: -
--

CREATE UNIQUE INDEX uq_users_email_casefold ON mobility_exchange.users USING btree (lower(email));


--
-- Name: active_legal_documents active_document_kind_insert; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER active_document_kind_insert BEFORE INSERT ON mobility_exchange.active_legal_documents FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_active_document_kind_insert();


--
-- Name: active_legal_documents active_document_kind_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER active_document_kind_update BEFORE UPDATE ON mobility_exchange.active_legal_documents FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_active_document_kind_update();


--
-- Name: appointments appointment_validate_insert; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER appointment_validate_insert BEFORE INSERT ON mobility_exchange.appointments FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_appointment_validate_insert();


--
-- Name: appointments appointment_validate_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER appointment_validate_update BEFORE UPDATE ON mobility_exchange.appointments FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_appointment_validate_update();


--
-- Name: audit_events audit_events_no_delete; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER audit_events_no_delete BEFORE DELETE ON mobility_exchange.audit_events FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_audit_events_no_delete();


--
-- Name: audit_events audit_events_no_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER audit_events_no_update BEFORE UPDATE ON mobility_exchange.audit_events FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_audit_events_no_update();


--
-- Name: signed_donor_certifications certification_document_kind; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER certification_document_kind BEFORE INSERT ON mobility_exchange.signed_donor_certifications FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_certification_document_kind();


--
-- Name: distributions distribution_complete; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER distribution_complete AFTER INSERT ON mobility_exchange.distributions FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_distribution_complete();


--
-- Name: distributions distribution_validate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER distribution_validate BEFORE INSERT ON mobility_exchange.distributions FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_distribution_validate();


--
-- Name: distributions distributions_clean_files; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER distributions_clean_files BEFORE INSERT ON mobility_exchange.distributions FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_distributions_clean_files();


--
-- Name: distributions distributions_no_delete; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER distributions_no_delete BEFORE DELETE ON mobility_exchange.distributions FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_distributions_no_delete();


--
-- Name: distributions distributions_no_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER distributions_no_update BEFORE UPDATE ON mobility_exchange.distributions FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_distributions_no_update();


--
-- Name: equipment equipment_history_insert; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER equipment_history_insert AFTER INSERT ON mobility_exchange.equipment FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_equipment_history_insert();


--
-- Name: equipment equipment_history_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER equipment_history_update AFTER UPDATE OF status_code ON mobility_exchange.equipment FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_equipment_history_update();


--
-- Name: equipment equipment_initial_status; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER equipment_initial_status BEFORE INSERT ON mobility_exchange.equipment FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_equipment_initial_status();


--
-- Name: equipment_status_history equipment_status_history_no_delete; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER equipment_status_history_no_delete BEFORE DELETE ON mobility_exchange.equipment_status_history FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_equipment_status_history_no_delete();


--
-- Name: equipment_status_history equipment_status_history_no_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER equipment_status_history_no_update BEFORE UPDATE ON mobility_exchange.equipment_status_history FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_equipment_status_history_no_update();


--
-- Name: equipment equipment_transition; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER equipment_transition BEFORE UPDATE OF status_code ON mobility_exchange.equipment FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_equipment_transition();


--
-- Name: files files_signed_no_delete; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER files_signed_no_delete BEFORE DELETE ON mobility_exchange.files FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_files_signed_no_delete();


--
-- Name: files files_signed_no_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER files_signed_no_update BEFORE UPDATE ON mobility_exchange.files FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_files_signed_no_update();


--
-- Name: legal_document_versions legal_document_versions_no_delete; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER legal_document_versions_no_delete BEFORE DELETE ON mobility_exchange.legal_document_versions FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_legal_document_versions_no_delete();


--
-- Name: legal_document_versions legal_document_versions_no_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER legal_document_versions_no_update BEFORE UPDATE ON mobility_exchange.legal_document_versions FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_legal_document_versions_no_update();


--
-- Name: active_legal_documents no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.active_legal_documents FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: appointment_slots no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.appointment_slots FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: appointments no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.appointments FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: audit_events no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.audit_events FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: content_pages no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.content_pages FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: conversation_participants no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.conversation_participants FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: conversations no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.conversations FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: distributions no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.distributions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: donors no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.donors FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: equipment no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.equipment FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: equipment_categories no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.equipment_categories FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: equipment_files no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.equipment_files FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: equipment_requests no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.equipment_requests FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: equipment_status_history no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.equipment_status_history FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: equipment_types no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.equipment_types FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: files no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.files FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: intake_item_files no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.intake_item_files FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: intake_items no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.intake_items FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: intake_submissions no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.intake_submissions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: inventory_statuses no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.inventory_statuses FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: inventory_transitions no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.inventory_transitions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: legal_document_versions no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.legal_document_versions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: location_closures no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.location_closures FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: location_hours no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.location_hours FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: locations no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.locations FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: message_files no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.message_files FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: messages no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.messages FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: notification_outbox no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.notification_outbox FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: organization_settings no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.organization_settings FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: permissions no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.permissions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: processing_events no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.processing_events FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: purchase_lines no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.purchase_lines FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: purchases no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.purchases FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: recipients no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.recipients FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: record_holds no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.record_holds FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: request_items no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.request_items FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: reservations no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.reservations FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: role_permissions no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.role_permissions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: roles no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.roles FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: schema_versions no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.schema_versions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: shift_signups no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.shift_signups FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: signed_donor_certifications no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.signed_donor_certifications FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: signed_waivers no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.signed_waivers FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: user_permission_grants no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.user_permission_grants FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: user_roles no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.user_roles FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: users no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.users FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: volunteer_shifts no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.volunteer_shifts FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: volunteers no_truncate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER no_truncate BEFORE TRUNCATE ON mobility_exchange.volunteers FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.reject_truncate();


--
-- Name: processing_events processing_events_no_delete; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER processing_events_no_delete BEFORE DELETE ON mobility_exchange.processing_events FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_processing_events_no_delete();


--
-- Name: processing_events processing_events_no_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER processing_events_no_update BEFORE UPDATE ON mobility_exchange.processing_events FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_processing_events_no_update();


--
-- Name: active_legal_documents require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.active_legal_documents FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: appointment_slots require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.appointment_slots FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: appointments require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.appointments FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: audit_events require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.audit_events FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: content_pages require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.content_pages FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: conversation_participants require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.conversation_participants FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: conversations require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.conversations FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: distributions require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.distributions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: donors require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.donors FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: equipment require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.equipment FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: equipment_categories require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.equipment_categories FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: equipment_files require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.equipment_files FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: equipment_requests require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.equipment_requests FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: equipment_status_history require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.equipment_status_history FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: equipment_types require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.equipment_types FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: files require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.files FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: intake_item_files require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.intake_item_files FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: intake_items require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.intake_items FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: intake_submissions require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.intake_submissions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: inventory_statuses require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.inventory_statuses FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: inventory_transitions require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.inventory_transitions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: legal_document_versions require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.legal_document_versions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: location_closures require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.location_closures FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: location_hours require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.location_hours FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: locations require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.locations FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: message_files require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.message_files FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: messages require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.messages FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: notification_outbox require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.notification_outbox FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: organization_settings require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.organization_settings FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: permissions require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.permissions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: processing_events require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.processing_events FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: purchase_lines require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.purchase_lines FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: purchases require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.purchases FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: recipients require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.recipients FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: record_holds require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.record_holds FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: request_items require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.request_items FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: reservations require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.reservations FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: role_permissions require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.role_permissions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: roles require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.roles FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: schema_versions require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.schema_versions FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: shift_signups require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.shift_signups FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: signed_donor_certifications require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.signed_donor_certifications FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: signed_waivers require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.signed_waivers FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: user_permission_grants require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.user_permission_grants FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: user_roles require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.user_roles FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: users require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.users FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: volunteer_shifts require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.volunteer_shifts FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: volunteers require_serializable; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER require_serializable BEFORE INSERT OR DELETE OR UPDATE ON mobility_exchange.volunteers FOR EACH STATEMENT EXECUTE FUNCTION mobility_exchange.require_serializable_write();


--
-- Name: reservations reservation_activate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER reservation_activate AFTER INSERT ON mobility_exchange.reservations FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_reservation_activate();


--
-- Name: reservations reservation_finish; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER reservation_finish BEFORE UPDATE OF status ON mobility_exchange.reservations FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_reservation_finish();


--
-- Name: reservations reservation_identity; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER reservation_identity BEFORE UPDATE ON mobility_exchange.reservations FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_reservation_identity();


--
-- Name: reservations reservation_no_delete; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER reservation_no_delete BEFORE DELETE ON mobility_exchange.reservations FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_reservation_no_delete();


--
-- Name: reservations reservation_release; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER reservation_release AFTER UPDATE OF status ON mobility_exchange.reservations FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_reservation_release();


--
-- Name: reservations reservation_validate; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER reservation_validate BEFORE INSERT ON mobility_exchange.reservations FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_reservation_validate();


--
-- Name: volunteer_shifts shift_cancel_signups; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER shift_cancel_signups AFTER UPDATE OF cancelled_at ON mobility_exchange.volunteer_shifts FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_shift_cancel_signups();


--
-- Name: volunteer_shifts shift_preserve_signups; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER shift_preserve_signups BEFORE UPDATE ON mobility_exchange.volunteer_shifts FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_shift_preserve_signups();


--
-- Name: signed_donor_certifications signed_donor_certifications_clean_files; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER signed_donor_certifications_clean_files BEFORE INSERT ON mobility_exchange.signed_donor_certifications FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_signed_donor_certifications_clean_files();


--
-- Name: signed_donor_certifications signed_donor_certifications_no_delete; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER signed_donor_certifications_no_delete BEFORE DELETE ON mobility_exchange.signed_donor_certifications FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_signed_donor_certifications_no_delete();


--
-- Name: signed_donor_certifications signed_donor_certifications_no_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER signed_donor_certifications_no_update BEFORE UPDATE ON mobility_exchange.signed_donor_certifications FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_signed_donor_certifications_no_update();


--
-- Name: signed_waivers signed_waivers_clean_files; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER signed_waivers_clean_files BEFORE INSERT ON mobility_exchange.signed_waivers FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_signed_waivers_clean_files();


--
-- Name: signed_waivers signed_waivers_no_delete; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER signed_waivers_no_delete BEFORE DELETE ON mobility_exchange.signed_waivers FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_signed_waivers_no_delete();


--
-- Name: signed_waivers signed_waivers_no_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER signed_waivers_no_update BEFORE UPDATE ON mobility_exchange.signed_waivers FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_signed_waivers_no_update();


--
-- Name: shift_signups signup_validate_insert; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER signup_validate_insert BEFORE INSERT ON mobility_exchange.shift_signups FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_signup_validate_insert();


--
-- Name: shift_signups signup_validate_update; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER signup_validate_update BEFORE UPDATE ON mobility_exchange.shift_signups FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_signup_validate_update();


--
-- Name: appointment_slots slot_preserve_bookings; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER slot_preserve_bookings BEFORE UPDATE ON mobility_exchange.appointment_slots FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_slot_preserve_bookings();


--
-- Name: signed_waivers waiver_document_kind; Type: TRIGGER; Schema: mobility_exchange; Owner: -
--

CREATE TRIGGER waiver_document_kind BEFORE INSERT ON mobility_exchange.signed_waivers FOR EACH ROW EXECUTE FUNCTION mobility_exchange.fn_waiver_document_kind();


--
-- Name: active_legal_documents active_legal_documents_version_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.active_legal_documents
    ADD CONSTRAINT active_legal_documents_version_id_fkey FOREIGN KEY (version_id) REFERENCES mobility_exchange.legal_document_versions(id);


--
-- Name: appointment_slots appointment_slots_created_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.appointment_slots
    ADD CONSTRAINT appointment_slots_created_by_fkey FOREIGN KEY (created_by) REFERENCES mobility_exchange.users(id);


--
-- Name: appointment_slots appointment_slots_location_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.appointment_slots
    ADD CONSTRAINT appointment_slots_location_id_fkey FOREIGN KEY (location_id) REFERENCES mobility_exchange.locations(id);


--
-- Name: appointments appointments_intake_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.appointments
    ADD CONSTRAINT appointments_intake_id_fkey FOREIGN KEY (intake_id) REFERENCES mobility_exchange.intake_submissions(id);


--
-- Name: appointments appointments_request_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.appointments
    ADD CONSTRAINT appointments_request_id_fkey FOREIGN KEY (request_id) REFERENCES mobility_exchange.equipment_requests(id);


--
-- Name: appointments appointments_slot_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.appointments
    ADD CONSTRAINT appointments_slot_id_fkey FOREIGN KEY (slot_id) REFERENCES mobility_exchange.appointment_slots(id);


--
-- Name: audit_events audit_events_actor_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.audit_events
    ADD CONSTRAINT audit_events_actor_user_id_fkey FOREIGN KEY (actor_user_id) REFERENCES mobility_exchange.users(id);


--
-- Name: content_pages content_pages_updated_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.content_pages
    ADD CONSTRAINT content_pages_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES mobility_exchange.users(id);


--
-- Name: conversation_participants conversation_participants_conversation_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.conversation_participants
    ADD CONSTRAINT conversation_participants_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES mobility_exchange.conversations(id);


--
-- Name: conversation_participants conversation_participants_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.conversation_participants
    ADD CONSTRAINT conversation_participants_user_id_fkey FOREIGN KEY (user_id) REFERENCES mobility_exchange.users(id);


--
-- Name: conversations conversations_assigned_to_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.conversations
    ADD CONSTRAINT conversations_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES mobility_exchange.users(id);


--
-- Name: conversations conversations_equipment_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.conversations
    ADD CONSTRAINT conversations_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES mobility_exchange.equipment(id);


--
-- Name: credentials credentials_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.credentials
    ADD CONSTRAINT credentials_user_id_fkey FOREIGN KEY (user_id) REFERENCES mobility_exchange.users(id);


--
-- Name: distributions distributions_appointment_id_request_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.distributions
    ADD CONSTRAINT distributions_appointment_id_request_id_fkey FOREIGN KEY (appointment_id, request_id) REFERENCES mobility_exchange.appointments(id, request_id);


--
-- Name: distributions distributions_pickup_signature_file_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.distributions
    ADD CONSTRAINT distributions_pickup_signature_file_id_fkey FOREIGN KEY (pickup_signature_file_id) REFERENCES mobility_exchange.files(id);


--
-- Name: distributions distributions_released_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.distributions
    ADD CONSTRAINT distributions_released_by_fkey FOREIGN KEY (released_by) REFERENCES mobility_exchange.users(id);


--
-- Name: distributions distributions_reservation_id_equipment_id_recipient_id_req_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.distributions
    ADD CONSTRAINT distributions_reservation_id_equipment_id_recipient_id_req_fkey FOREIGN KEY (reservation_id, equipment_id, recipient_id, request_id) REFERENCES mobility_exchange.reservations(id, equipment_id, recipient_id, request_id);


--
-- Name: distributions distributions_waiver_id_recipient_id_request_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.distributions
    ADD CONSTRAINT distributions_waiver_id_recipient_id_request_id_fkey FOREIGN KEY (waiver_id, recipient_id, request_id) REFERENCES mobility_exchange.signed_waivers(id, recipient_id, request_id);


--
-- Name: donors donors_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.donors
    ADD CONSTRAINT donors_user_id_fkey FOREIGN KEY (user_id) REFERENCES mobility_exchange.users(id);


--
-- Name: equipment equipment_assigned_volunteer_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment
    ADD CONSTRAINT equipment_assigned_volunteer_id_fkey FOREIGN KEY (assigned_volunteer_id) REFERENCES mobility_exchange.volunteers(user_id);


--
-- Name: equipment equipment_created_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment
    ADD CONSTRAINT equipment_created_by_fkey FOREIGN KEY (created_by) REFERENCES mobility_exchange.users(id);


--
-- Name: equipment_files equipment_files_approved_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_files
    ADD CONSTRAINT equipment_files_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES mobility_exchange.users(id);


--
-- Name: equipment_files equipment_files_equipment_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_files
    ADD CONSTRAINT equipment_files_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES mobility_exchange.equipment(id);


--
-- Name: equipment_files equipment_files_file_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_files
    ADD CONSTRAINT equipment_files_file_id_fkey FOREIGN KEY (file_id) REFERENCES mobility_exchange.files(id);


--
-- Name: equipment equipment_intake_item_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment
    ADD CONSTRAINT equipment_intake_item_id_fkey FOREIGN KEY (intake_item_id) REFERENCES mobility_exchange.intake_items(id);


--
-- Name: equipment equipment_location_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment
    ADD CONSTRAINT equipment_location_id_fkey FOREIGN KEY (location_id) REFERENCES mobility_exchange.locations(id);


--
-- Name: equipment equipment_purchase_line_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment
    ADD CONSTRAINT equipment_purchase_line_id_fkey FOREIGN KEY (purchase_line_id) REFERENCES mobility_exchange.purchase_lines(id);


--
-- Name: equipment_requests equipment_requests_recipient_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_requests
    ADD CONSTRAINT equipment_requests_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES mobility_exchange.recipients(id);


--
-- Name: equipment_requests equipment_requests_requested_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_requests
    ADD CONSTRAINT equipment_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES mobility_exchange.users(id);


--
-- Name: equipment_requests equipment_requests_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_requests
    ADD CONSTRAINT equipment_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES mobility_exchange.users(id);


--
-- Name: equipment equipment_status_code_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment
    ADD CONSTRAINT equipment_status_code_fkey FOREIGN KEY (status_code) REFERENCES mobility_exchange.inventory_statuses(code);


--
-- Name: equipment_status_history equipment_status_history_actor_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_status_history
    ADD CONSTRAINT equipment_status_history_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES mobility_exchange.users(id);


--
-- Name: equipment_status_history equipment_status_history_equipment_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_status_history
    ADD CONSTRAINT equipment_status_history_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES mobility_exchange.equipment(id);


--
-- Name: equipment_status_history equipment_status_history_from_status_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_status_history
    ADD CONSTRAINT equipment_status_history_from_status_fkey FOREIGN KEY (from_status) REFERENCES mobility_exchange.inventory_statuses(code);


--
-- Name: equipment_status_history equipment_status_history_to_status_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_status_history
    ADD CONSTRAINT equipment_status_history_to_status_fkey FOREIGN KEY (to_status) REFERENCES mobility_exchange.inventory_statuses(code);


--
-- Name: equipment equipment_type_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment
    ADD CONSTRAINT equipment_type_id_fkey FOREIGN KEY (type_id) REFERENCES mobility_exchange.equipment_types(id);


--
-- Name: equipment_types equipment_types_category_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment_types
    ADD CONSTRAINT equipment_types_category_id_fkey FOREIGN KEY (category_id) REFERENCES mobility_exchange.equipment_categories(id);


--
-- Name: equipment equipment_updated_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.equipment
    ADD CONSTRAINT equipment_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES mobility_exchange.users(id);


--
-- Name: files files_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.files
    ADD CONSTRAINT files_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES mobility_exchange.users(id);


--
-- Name: intake_item_files intake_item_files_file_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_item_files
    ADD CONSTRAINT intake_item_files_file_id_fkey FOREIGN KEY (file_id) REFERENCES mobility_exchange.files(id);


--
-- Name: intake_item_files intake_item_files_intake_item_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_item_files
    ADD CONSTRAINT intake_item_files_intake_item_id_fkey FOREIGN KEY (intake_item_id) REFERENCES mobility_exchange.intake_items(id);


--
-- Name: intake_items intake_items_intake_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_items
    ADD CONSTRAINT intake_items_intake_id_fkey FOREIGN KEY (intake_id) REFERENCES mobility_exchange.intake_submissions(id);


--
-- Name: intake_items intake_items_type_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_items
    ADD CONSTRAINT intake_items_type_id_fkey FOREIGN KEY (type_id) REFERENCES mobility_exchange.equipment_types(id);


--
-- Name: intake_submissions intake_submissions_donor_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_submissions
    ADD CONSTRAINT intake_submissions_donor_id_fkey FOREIGN KEY (donor_id) REFERENCES mobility_exchange.donors(id);


--
-- Name: intake_submissions intake_submissions_preferred_location_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_submissions
    ADD CONSTRAINT intake_submissions_preferred_location_id_fkey FOREIGN KEY (preferred_location_id) REFERENCES mobility_exchange.locations(id);


--
-- Name: intake_submissions intake_submissions_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_submissions
    ADD CONSTRAINT intake_submissions_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES mobility_exchange.users(id);


--
-- Name: intake_submissions intake_submissions_submitted_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.intake_submissions
    ADD CONSTRAINT intake_submissions_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES mobility_exchange.users(id);


--
-- Name: inventory_transitions inventory_transitions_from_status_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.inventory_transitions
    ADD CONSTRAINT inventory_transitions_from_status_fkey FOREIGN KEY (from_status) REFERENCES mobility_exchange.inventory_statuses(code);


--
-- Name: inventory_transitions inventory_transitions_to_status_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.inventory_transitions
    ADD CONSTRAINT inventory_transitions_to_status_fkey FOREIGN KEY (to_status) REFERENCES mobility_exchange.inventory_statuses(code);


--
-- Name: legal_document_versions legal_document_versions_published_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.legal_document_versions
    ADD CONSTRAINT legal_document_versions_published_by_fkey FOREIGN KEY (published_by) REFERENCES mobility_exchange.users(id);


--
-- Name: location_closures location_closures_location_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.location_closures
    ADD CONSTRAINT location_closures_location_id_fkey FOREIGN KEY (location_id) REFERENCES mobility_exchange.locations(id);


--
-- Name: location_hours location_hours_location_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.location_hours
    ADD CONSTRAINT location_hours_location_id_fkey FOREIGN KEY (location_id) REFERENCES mobility_exchange.locations(id);


--
-- Name: login_sessions login_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.login_sessions
    ADD CONSTRAINT login_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES mobility_exchange.users(id);


--
-- Name: message_files message_files_file_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.message_files
    ADD CONSTRAINT message_files_file_id_fkey FOREIGN KEY (file_id) REFERENCES mobility_exchange.files(id);


--
-- Name: message_files message_files_message_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.message_files
    ADD CONSTRAINT message_files_message_id_fkey FOREIGN KEY (message_id) REFERENCES mobility_exchange.messages(id);


--
-- Name: messages messages_conversation_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.messages
    ADD CONSTRAINT messages_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES mobility_exchange.conversations(id);


--
-- Name: messages messages_sender_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.messages
    ADD CONSTRAINT messages_sender_user_id_fkey FOREIGN KEY (sender_user_id) REFERENCES mobility_exchange.users(id);


--
-- Name: notification_outbox notification_outbox_recipient_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.notification_outbox
    ADD CONSTRAINT notification_outbox_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES mobility_exchange.users(id);


--
-- Name: organization_settings organization_settings_updated_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.organization_settings
    ADD CONSTRAINT organization_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES mobility_exchange.users(id);


--
-- Name: processing_events processing_events_equipment_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.processing_events
    ADD CONSTRAINT processing_events_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES mobility_exchange.equipment(id);


--
-- Name: processing_events processing_events_performed_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.processing_events
    ADD CONSTRAINT processing_events_performed_by_fkey FOREIGN KEY (performed_by) REFERENCES mobility_exchange.users(id);


--
-- Name: processing_events processing_events_supersedes_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.processing_events
    ADD CONSTRAINT processing_events_supersedes_id_fkey FOREIGN KEY (supersedes_id) REFERENCES mobility_exchange.processing_events(id);


--
-- Name: purchase_lines purchase_lines_purchase_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.purchase_lines
    ADD CONSTRAINT purchase_lines_purchase_id_fkey FOREIGN KEY (purchase_id) REFERENCES mobility_exchange.purchases(id);


--
-- Name: purchase_lines purchase_lines_type_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.purchase_lines
    ADD CONSTRAINT purchase_lines_type_id_fkey FOREIGN KEY (type_id) REFERENCES mobility_exchange.equipment_types(id);


--
-- Name: purchases purchases_created_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.purchases
    ADD CONSTRAINT purchases_created_by_fkey FOREIGN KEY (created_by) REFERENCES mobility_exchange.users(id);


--
-- Name: purchases purchases_receipt_file_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.purchases
    ADD CONSTRAINT purchases_receipt_file_id_fkey FOREIGN KEY (receipt_file_id) REFERENCES mobility_exchange.files(id);


--
-- Name: recipients recipients_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.recipients
    ADD CONSTRAINT recipients_user_id_fkey FOREIGN KEY (user_id) REFERENCES mobility_exchange.users(id);


--
-- Name: record_holds record_holds_placed_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.record_holds
    ADD CONSTRAINT record_holds_placed_by_fkey FOREIGN KEY (placed_by) REFERENCES mobility_exchange.users(id);


--
-- Name: record_holds record_holds_released_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.record_holds
    ADD CONSTRAINT record_holds_released_by_fkey FOREIGN KEY (released_by) REFERENCES mobility_exchange.users(id);


--
-- Name: request_items request_items_equipment_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.request_items
    ADD CONSTRAINT request_items_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES mobility_exchange.equipment(id);


--
-- Name: request_items request_items_request_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.request_items
    ADD CONSTRAINT request_items_request_id_fkey FOREIGN KEY (request_id) REFERENCES mobility_exchange.equipment_requests(id);


--
-- Name: reservations reservations_closed_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.reservations
    ADD CONSTRAINT reservations_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES mobility_exchange.users(id);


--
-- Name: reservations reservations_request_id_recipient_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.reservations
    ADD CONSTRAINT reservations_request_id_recipient_id_fkey FOREIGN KEY (request_id, recipient_id) REFERENCES mobility_exchange.equipment_requests(id, recipient_id);


--
-- Name: reservations reservations_request_item_id_request_id_equipment_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.reservations
    ADD CONSTRAINT reservations_request_item_id_request_id_equipment_id_fkey FOREIGN KEY (request_item_id, request_id, equipment_id) REFERENCES mobility_exchange.request_items(id, request_id, equipment_id);


--
-- Name: reservations reservations_reserved_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.reservations
    ADD CONSTRAINT reservations_reserved_by_fkey FOREIGN KEY (reserved_by) REFERENCES mobility_exchange.users(id);


--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES mobility_exchange.permissions(id);


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES mobility_exchange.roles(id);


--
-- Name: shift_signups shift_signups_attendance_recorded_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.shift_signups
    ADD CONSTRAINT shift_signups_attendance_recorded_by_fkey FOREIGN KEY (attendance_recorded_by) REFERENCES mobility_exchange.users(id);


--
-- Name: shift_signups shift_signups_shift_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.shift_signups
    ADD CONSTRAINT shift_signups_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES mobility_exchange.volunteer_shifts(id);


--
-- Name: shift_signups shift_signups_volunteer_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.shift_signups
    ADD CONSTRAINT shift_signups_volunteer_id_fkey FOREIGN KEY (volunteer_id) REFERENCES mobility_exchange.volunteers(user_id);


--
-- Name: signed_donor_certifications signed_donor_certifications_intake_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_donor_certifications
    ADD CONSTRAINT signed_donor_certifications_intake_id_fkey FOREIGN KEY (intake_id) REFERENCES mobility_exchange.intake_submissions(id);


--
-- Name: signed_donor_certifications signed_donor_certifications_signature_evidence_file_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_donor_certifications
    ADD CONSTRAINT signed_donor_certifications_signature_evidence_file_id_fkey FOREIGN KEY (signature_evidence_file_id) REFERENCES mobility_exchange.files(id);


--
-- Name: signed_donor_certifications signed_donor_certifications_signed_pdf_file_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_donor_certifications
    ADD CONSTRAINT signed_donor_certifications_signed_pdf_file_id_fkey FOREIGN KEY (signed_pdf_file_id) REFERENCES mobility_exchange.files(id);


--
-- Name: signed_donor_certifications signed_donor_certifications_version_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_donor_certifications
    ADD CONSTRAINT signed_donor_certifications_version_id_fkey FOREIGN KEY (version_id) REFERENCES mobility_exchange.legal_document_versions(id);


--
-- Name: signed_waivers signed_waivers_recipient_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_waivers
    ADD CONSTRAINT signed_waivers_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES mobility_exchange.recipients(id);


--
-- Name: signed_waivers signed_waivers_request_id_recipient_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_waivers
    ADD CONSTRAINT signed_waivers_request_id_recipient_id_fkey FOREIGN KEY (request_id, recipient_id) REFERENCES mobility_exchange.equipment_requests(id, recipient_id);


--
-- Name: signed_waivers signed_waivers_signature_evidence_file_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_waivers
    ADD CONSTRAINT signed_waivers_signature_evidence_file_id_fkey FOREIGN KEY (signature_evidence_file_id) REFERENCES mobility_exchange.files(id);


--
-- Name: signed_waivers signed_waivers_signed_pdf_file_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_waivers
    ADD CONSTRAINT signed_waivers_signed_pdf_file_id_fkey FOREIGN KEY (signed_pdf_file_id) REFERENCES mobility_exchange.files(id);


--
-- Name: signed_waivers signed_waivers_version_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.signed_waivers
    ADD CONSTRAINT signed_waivers_version_id_fkey FOREIGN KEY (version_id) REFERENCES mobility_exchange.legal_document_versions(id);


--
-- Name: user_permission_grants user_permission_grants_granted_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.user_permission_grants
    ADD CONSTRAINT user_permission_grants_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES mobility_exchange.users(id);


--
-- Name: user_permission_grants user_permission_grants_permission_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.user_permission_grants
    ADD CONSTRAINT user_permission_grants_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES mobility_exchange.permissions(id);


--
-- Name: user_permission_grants user_permission_grants_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.user_permission_grants
    ADD CONSTRAINT user_permission_grants_user_id_fkey FOREIGN KEY (user_id) REFERENCES mobility_exchange.users(id);


--
-- Name: user_roles user_roles_assigned_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.user_roles
    ADD CONSTRAINT user_roles_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES mobility_exchange.users(id);


--
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES mobility_exchange.roles(id);


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES mobility_exchange.users(id);


--
-- Name: volunteer_shifts volunteer_shifts_created_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.volunteer_shifts
    ADD CONSTRAINT volunteer_shifts_created_by_fkey FOREIGN KEY (created_by) REFERENCES mobility_exchange.users(id);


--
-- Name: volunteer_shifts volunteer_shifts_location_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.volunteer_shifts
    ADD CONSTRAINT volunteer_shifts_location_id_fkey FOREIGN KEY (location_id) REFERENCES mobility_exchange.locations(id);


--
-- Name: volunteers volunteers_approved_by_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.volunteers
    ADD CONSTRAINT volunteers_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES mobility_exchange.users(id);


--
-- Name: volunteers volunteers_user_id_fkey; Type: FK CONSTRAINT; Schema: mobility_exchange; Owner: -
--

ALTER TABLE ONLY mobility_exchange.volunteers
    ADD CONSTRAINT volunteers_user_id_fkey FOREIGN KEY (user_id) REFERENCES mobility_exchange.users(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO public,mobility_exchange;

INSERT INTO "schema_migrations" (version) VALUES
('20260915000000'),
('20260912010000'),
('20260912000000'),
('20260911000100'),
('20260911000000');

