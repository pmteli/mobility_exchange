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
-- Name: freedme; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA freedme;


--
-- Name: enqueue_handoff_followups(timestamp with time zone); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.enqueue_handoff_followups(as_of timestamp with time zone DEFAULT now()) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO 'freedme', 'pg_catalog'
    AS $$
DECLARE n integer;
BEGIN
 INSERT INTO moderator_tasks(exchange_id,kind,due_at)
 SELECT e.id,'unconfirmed_handoff',e.reserved_at+interval '168 hours' FROM exchanges e
 WHERE e.state='reserved' AND e.reserved_at+interval '168 hours'<=as_of
 AND NOT EXISTS(SELECT 1 FROM exchange_events v WHERE v.exchange_id=e.id AND v.event_type='handoff_confirmed')
 ON CONFLICT(exchange_id,kind) DO NOTHING;
 GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
END $$;


--
-- Name: evidence_collection_gate(); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.evidence_collection_gate() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'freedme', 'pg_catalog'
    AS $$
BEGIN
 IF NOT EXISTS (SELECT 1 FROM pilot_controls c JOIN policy_versions p ON p.id=c.privacy_policy_id
   WHERE c.evidence_collection_enabled AND p.approved_at IS NOT NULL AND p.effective_at <= now()) THEN
  RAISE EXCEPTION 'Identity evidence collection is disabled pending approved privacy controls';
 END IF;
 RETURN NEW;
END $$;


--
-- Name: frozen_revision(); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.frozen_revision() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'freedme', 'pg_catalog'
    AS $$
BEGIN
 IF OLD.submitted_at IS NOT NULL THEN
  RAISE EXCEPTION 'Submitted revisions are immutable; create a new revision';
 END IF;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;


--
-- Name: guard_exchange(); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.guard_exchange() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'freedme', 'pg_catalog'
    AS $$
DECLARE l listings; r listing_revisions;
BEGIN
 -- All competing allocations serialize on the item, in addition to the partial unique index.
 SELECT * INTO l FROM listings WHERE id=NEW.listing_id FOR UPDATE;
 SELECT * INTO r FROM listing_revisions WHERE id=NEW.revision_id;
 IF TG_OP='INSERT' THEN
  IF NEW.state<>'pending' OR l.status<>'available' OR l.approved_revision_id IS DISTINCT FROM NEW.revision_id THEN
   RAISE EXCEPTION 'New requests require available approved inventory and pending state';
  END IF;
  IF l.availability_valid_until IS NULL OR l.availability_valid_until<=now() THEN
   RAISE EXCEPTION 'Availability must be fresh under an approved renewal policy';
  END IF;
 ELSE
  IF (NEW.listing_id,NEW.donor_id,NEW.requester_id,NEW.revision_id,NEW.representation_id,NEW.requested_at,NEW.idempotency_key)
    IS DISTINCT FROM (OLD.listing_id,OLD.donor_id,OLD.requester_id,OLD.revision_id,OLD.representation_id,OLD.requested_at,OLD.idempotency_key) THEN
   RAISE EXCEPTION 'Exchange identity and requested revision are immutable';
  END IF;
  IF NEW.state IS DISTINCT FROM OLD.state AND NOT (
   (OLD.state='pending' AND NEW.state IN ('offered','declined','expired','cancelled','closed_unavailable')) OR
   (OLD.state='offered' AND NEW.state IN ('reserved','expired','cancelled','closed_unavailable')) OR
   (OLD.state='reserved' AND NEW.state IN ('loaned','completed','cancelled','closed_unavailable')) OR
   (OLD.state='loaned' AND NEW.state IN ('completed','closed_unavailable'))
  ) THEN RAISE EXCEPTION 'Invalid exchange transition: % to %',OLD.state,NEW.state; END IF;
  IF NEW.state='offered' AND OLD.state='pending' AND now()>=OLD.pending_expires_at THEN
   RAISE EXCEPTION 'Pending request expired';
  END IF;
  IF NEW.state='reserved' AND OLD.state='offered' AND now()>=OLD.offer_expires_at THEN
   RAISE EXCEPTION 'Offer expired';
  END IF;
 END IF;
 IF NEW.state IN ('pending','offered','reserved','loaned') THEN
  IF EXISTS(SELECT 1 FROM restrictions WHERE released_at IS NULL AND (listing_id=l.id OR account_id IN (NEW.donor_id,NEW.requester_id)))
    OR EXISTS(SELECT 1 FROM accounts WHERE id IN (NEW.donor_id,NEW.requester_id) AND status<>'active') THEN
   -- Holds can be imposed after allocation; closure remains possible.
   RAISE EXCEPTION 'Account or listing restriction blocks allocation progression';
  END IF;
 END IF;
 IF r.offer_kind='gift' AND (NEW.requested_loan_days IS NOT NULL OR NEW.state='loaned') THEN
  RAISE EXCEPTION 'Gifts do not carry loan periods or loaned state';
 ELSIF r.offer_kind='loan' THEN
  IF NEW.proposed_end_date IS NULL OR NEW.proposed_start_date IS NULL OR NEW.proposed_end_date>r.loan_until THEN
   RAISE EXCEPTION 'Requested calendar dates missing or beyond Loan Until';
  END IF;
  IF TG_OP='INSERT' AND NOT EXISTS(SELECT 1 FROM pilot_controls c JOIN policy_versions p ON p.id=c.loan_policy_id
    WHERE c.loans_enabled AND p.approved_at IS NOT NULL AND p.effective_at<=now()) THEN
   RAISE EXCEPTION 'Loans are disabled pending approved controls';
  END IF;
 END IF;
 RETURN NEW;
END $$;


--
-- Name: guard_handoff_acceptance(); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.guard_handoff_acceptance() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'freedme', 'pg_catalog'
    AS $$
DECLARE ex exchanges; prop handoff_proposals;
BEGIN
 SELECT * INTO ex FROM exchanges WHERE id=NEW.exchange_id FOR UPDATE;
 SELECT * INTO prop FROM handoff_proposals WHERE id=NEW.proposal_id AND exchange_id=NEW.exchange_id;
 IF prop.id IS NULL OR ex.state NOT IN ('offered','reserved') OR ex.paused_reason IS NOT NULL
 OR NEW.accepted_by NOT IN(ex.donor_id,ex.requester_id) OR NEW.accepted_by=prop.proposed_by
 OR prop.meeting_at<=now() OR prop.revision<>(SELECT max(revision) FROM handoff_proposals WHERE exchange_id=ex.id)
 THEN RAISE EXCEPTION 'Acceptance requires current future proposal and opposite participant'; END IF;
 IF EXISTS(SELECT 1 FROM restrictions WHERE released_at IS NULL AND (listing_id=ex.listing_id OR account_id IN(ex.donor_id,ex.requester_id))) THEN RAISE EXCEPTION 'Handoff blocked by restriction'; END IF;
 RETURN NEW;
END $$;


--
-- Name: guard_handoff_proposal(); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.guard_handoff_proposal() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'freedme', 'pg_catalog'
    AS $$
DECLARE ex exchanges; latest integer;
BEGIN
 SELECT * INTO ex FROM exchanges WHERE id=NEW.exchange_id FOR UPDATE;
 IF ex.state NOT IN ('offered','reserved') OR ex.paused_reason IS NOT NULL
 OR NEW.proposed_by NOT IN (ex.donor_id,ex.requester_id) THEN RAISE EXCEPTION 'Handoff proposal requires an active participant and offer/reservation'; END IF;
 IF EXISTS(SELECT 1 FROM restrictions WHERE released_at IS NULL AND (listing_id=ex.listing_id OR account_id IN(ex.donor_id,ex.requester_id))) THEN RAISE EXCEPTION 'Handoff blocked by restriction'; END IF;
 SELECT coalesce(max(revision),0) INTO latest FROM handoff_proposals WHERE exchange_id=ex.id;
 IF NEW.revision<>latest+1 THEN RAISE EXCEPTION 'Stale proposal revision'; END IF;
 IF NEW.meeting_at<=now() THEN RAISE EXCEPTION 'Meeting must be in the future'; END IF;
 IF NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=NEW.display_timezone) THEN RAISE EXCEPTION 'Unknown timezone'; END IF;
 RETURN NEW;
END $$;


--
-- Name: guard_publication(); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.guard_publication() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'freedme', 'pg_catalog'
    AS $$
DECLARE r listing_revisions; photo_count integer;
BEGIN
 IF NEW.status <> 'available' THEN RETURN NEW; END IF;
 SELECT * INTO r FROM listing_revisions WHERE id=NEW.approved_revision_id AND listing_id=NEW.id;
 IF NOT FOUND OR NEW.current_revision_id IS DISTINCT FROM NEW.approved_revision_id
   OR r.submitted_at IS NULL OR NOT r.free_item_affirmed OR NOT r.truthfulness_affirmed
   OR r.public_content_checked_at IS NULL OR NOT r.no_missing_parts_affirmed THEN
  RAISE EXCEPTION 'Available inventory requires a submitted screened revision';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM equipment_configurations c JOIN policy_versions p ON p.id=c.policy_id
   JOIN policy_versions g ON g.id=c.guidance_policy_id WHERE c.id=r.configuration_id AND c.allowed
   AND p.approved_at IS NOT NULL AND p.effective_at<=now() AND g.approved_at IS NOT NULL AND g.effective_at<=now()) THEN
  RAISE EXCEPTION 'Equipment configuration and guidance not approved';
 END IF;
 IF NOT EXISTS (SELECT 1 FROM service_areas a JOIN policy_versions p ON p.id=a.policy_id WHERE a.id=r.service_area_id
   AND a.donor_eligible AND p.approved_at IS NOT NULL AND p.effective_at<=now()) THEN
  RAISE EXCEPTION 'Donor service area not approved';
 END IF;
 SELECT count(*) INTO photo_count FROM listing_photos WHERE revision_id=r.id AND state='approved';
 IF photo_count NOT BETWEEN 1 AND 5 OR EXISTS(SELECT 1 FROM listing_photos WHERE revision_id=r.id AND state<>'approved') THEN
  RAISE EXCEPTION 'One to five approved sanitized photos required';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM listing_reviews WHERE revision_id=r.id AND decision='approved' AND disclosures_checked AND recall_checked)
 OR NOT EXISTS(SELECT 1 FROM recall_reviews WHERE revision_id=r.id)
 OR EXISTS(SELECT 1 FROM recall_reviews WHERE revision_id=r.id AND result NOT IN ('no_match','resolved_under_policy')) THEN
  RAISE EXCEPTION 'Recorded disclosure and recall clearance required';
 END IF;
 IF EXISTS(SELECT 1 FROM restrictions WHERE released_at IS NULL AND (listing_id=NEW.id OR account_id=NEW.donor_id))
 OR NOT EXISTS(SELECT 1 FROM accounts WHERE id=NEW.donor_id AND status='active') THEN
  RAISE EXCEPTION 'Restricted item or owner cannot publish';
 END IF;
 IF EXISTS(SELECT 1 FROM exchanges WHERE listing_id=NEW.id AND state IN ('pending','offered','reserved','loaned')) THEN
  RAISE EXCEPTION 'Prior allocation must be closed before reopening';
 END IF;
 IF TG_OP='UPDATE' AND OLD.status IN ('reserved','loaned','unavailable','donated','withdrawn') THEN
  IF NEW.last_possession_confirmed_at IS NULL OR NEW.last_possession_confirmed_at <= OLD.updated_at
    OR NEW.allocation_generation <= OLD.allocation_generation THEN
   RAISE EXCEPTION 'Reopening requires fresh owner possession affirmation and link-generation increment';
  END IF;
 END IF;
 NEW.updated_at:=clock_timestamp();
 RETURN NEW;
END $$;


--
-- Name: guard_transfer_event(); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.guard_transfer_event() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'freedme', 'pg_catalog'
    AS $$
DECLARE ex exchanges;
BEGIN
 SELECT * INTO ex FROM exchanges WHERE id=NEW.exchange_id FOR UPDATE;
 IF NEW.event_type='handoff_confirmed' THEN
  IF NEW.actor_id IS NULL OR NEW.actor_id NOT IN(ex.donor_id,ex.requester_id) OR ex.state NOT IN('reserved','loaned','completed')
  THEN RAISE EXCEPTION 'Only a participant may confirm a reserved handoff'; END IF;
 ELSIF NEW.event_type='return_confirmed' THEN
  IF (NEW.actor_id IS NULL OR NEW.actor_id NOT IN(ex.donor_id,ex.requester_id)) OR ex.state NOT IN('loaned','completed')
  THEN RAISE EXCEPTION 'Only an authorized participant may confirm loan return'; END IF;
 END IF;
 RETURN NEW;
END $$;


--
-- Name: prevent_history_mutation(); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.prevent_history_mutation() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN RAISE EXCEPTION 'History is append-only; approved retention maintenance uses a separate owner-controlled process'; END $$;


--
-- Name: read_donor_identity(uuid, uuid); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.read_donor_identity(actor uuid, requested_exchange uuid) RETURNS TABLE(field_name text, value_ciphertext bytea, key_version text)
    LANGUAGE plpgsql
    SET search_path TO 'freedme', 'pg_catalog'
    AS $$
DECLARE selected_grant disclosure_grants; permitted boolean;
BEGIN
 SELECT g.* INTO selected_grant FROM disclosure_grants g
 JOIN exchanges e ON e.id=g.exchange_id JOIN identity_evidence v ON v.id=g.evidence_id
 WHERE e.id=requested_exchange AND e.donor_id=actor AND g.donor_id=actor
 AND g.consented_by=e.requester_id AND v.submitted_by=e.requester_id
 AND e.state IN('pending','offered','reserved','loaned') AND e.paused_reason IS NULL
 AND g.revoked_at IS NULL AND g.expires_at>now() AND v.review_state='approved' AND v.valid_until>now()
 ORDER BY g.granted_at DESC,g.id DESC LIMIT 1;
 permitted:=FOUND;
 INSERT INTO sensitive_access_events(actor_id,grant_id,evidence_id,purpose,allowed,field_names)
 VALUES(actor,selected_grant.id,selected_grant.evidence_id,'donor_request_review',permitted,
 CASE WHEN permitted THEN ARRAY['first_name','last_name','zip_code']::text[] ELSE '{}'::text[] END);
 IF NOT permitted THEN RETURN; END IF;
 RETURN QUERY SELECT bf.field_name,bf.value_ciphertext,bf.key_version FROM borrower_fields bf
 WHERE bf.evidence_id=selected_grant.evidence_id
 AND bf.field_name IN('first_name','last_name','zip_code') AND bf.field_name=ANY(selected_grant.allowed_fields)
 AND bf.source='document' AND bf.verification='reviewed_against_evidence';
END $$;


--
-- Name: validate_verified_request(); Type: FUNCTION; Schema: freedme; Owner: -
--

CREATE FUNCTION freedme.validate_verified_request() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'freedme', 'pg_catalog'
    AS $$
DECLARE e exchanges;
BEGIN
 SELECT * INTO e FROM exchanges WHERE id=NEW.id;
 IF e.state NOT IN ('pending','offered','reserved') THEN RETURN NULL; END IF;
 IF NOT EXISTS(SELECT 1 FROM disclosure_grants g JOIN identity_evidence v ON v.id=g.evidence_id
  JOIN policy_versions p ON p.id=g.consent_policy_id
  WHERE g.exchange_id=e.id AND g.donor_id=e.donor_id AND g.consented_by=e.requester_id
   AND v.submitted_by=e.requester_id AND v.representation_id IS NOT DISTINCT FROM e.representation_id
   AND v.review_state='approved' AND v.valid_until>now() AND g.expires_at>now()
   AND g.revoked_at IS NULL AND p.approved_at IS NOT NULL AND p.effective_at<=now()
   AND ARRAY['first_name','last_name','zip_code']::text[] <@ g.allowed_fields
   AND (SELECT count(*) FROM borrower_fields bf WHERE bf.evidence_id=v.id
        AND bf.field_name IN ('first_name','last_name','home_address','zip_code')
        AND bf.source='document' AND bf.verification='reviewed_against_evidence')=4) THEN
  RAISE EXCEPTION 'Current verified identity evidence and request-specific consent required';
 END IF;
 RETURN NULL;
END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: account_contacts; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.account_contacts (
    id uuid DEFAULT uuidv7() NOT NULL,
    account_id uuid NOT NULL,
    kind text NOT NULL,
    value_ciphertext bytea NOT NULL,
    lookup_hmac bytea NOT NULL,
    key_version text NOT NULL,
    verified_at timestamp with time zone,
    revoked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    staff_notification boolean DEFAULT false NOT NULL,
    CONSTRAINT account_contacts_kind_check CHECK ((kind = ANY (ARRAY['mobile'::text, 'email'::text])))
);


--
-- Name: account_notices; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.account_notices (
    id uuid DEFAULT uuidv7() NOT NULL,
    account_id uuid NOT NULL,
    exchange_id uuid,
    listing_id uuid,
    notice_type text NOT NULL,
    reason_code text,
    due_at timestamp with time zone,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    idempotency_key text NOT NULL
);


--
-- Name: account_roles; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.account_roles (
    account_id uuid NOT NULL,
    role text NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    granted_by uuid,
    CONSTRAINT account_roles_role_check CHECK ((role = ANY (ARRAY['donor'::text, 'recipient'::text, 'caregiver'::text, 'helper'::text, 'moderator'::text, 'support'::text, 'administrator'::text])))
);


--
-- Name: accounts; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.accounts (
    id uuid DEFAULT uuidv7() NOT NULL,
    display_name text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    public_locality text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    closed_at timestamp with time zone,
    last_activity_at timestamp(6) without time zone,
    last_inactivity_reviewed_at timestamp(6) without time zone,
    CONSTRAINT accounts_display_name_check CHECK (((length(TRIM(BOTH FROM display_name)) >= 1) AND (length(TRIM(BOTH FROM display_name)) <= 80))),
    CONSTRAINT accounts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'restricted'::text, 'closed'::text])))
);


--
-- Name: action_tokens; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.action_tokens (
    id uuid DEFAULT uuidv7() NOT NULL,
    account_id uuid,
    exchange_id uuid,
    case_id uuid,
    purpose text NOT NULL,
    token_digest bytea NOT NULL,
    allocation_generation integer,
    expires_at timestamp with time zone NOT NULL,
    used_at timestamp with time zone,
    revoked_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT action_tokens_check CHECK ((expires_at > created_at))
);


--
-- Name: activity_events; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.activity_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    account_id uuid NOT NULL,
    action text NOT NULL,
    accepted boolean NOT NULL,
    policy_id uuid,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    idempotency_key text NOT NULL
);


--
-- Name: agreements; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.agreements (
    id uuid DEFAULT uuidv7() NOT NULL,
    exchange_id uuid NOT NULL,
    terms_policy_id uuid NOT NULL,
    accepted_by uuid NOT NULL,
    accepted_at timestamp with time zone NOT NULL,
    terms_snapshot_ciphertext bytea NOT NULL,
    key_version text NOT NULL,
    snapshot_sha256 text NOT NULL
);


--
-- Name: audit_events; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.audit_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    actor_id uuid,
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    reason_code text,
    correlation_id uuid NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: auth_challenges; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.auth_challenges (
    id uuid DEFAULT uuidv7() NOT NULL,
    account_id uuid,
    phone_lookup_hmac bytea NOT NULL,
    code_digest bytea NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    failed_attempts smallint DEFAULT 0 NOT NULL,
    consumed_at timestamp with time zone,
    invalidated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    provider character varying DEFAULT 'simulated'::character varying NOT NULL,
    provider_sid character varying,
    CONSTRAINT auth_challenges_check CHECK ((expires_at > created_at)),
    CONSTRAINT auth_challenges_check1 CHECK (((failed_attempts < 3) OR (invalidated_at IS NOT NULL))),
    CONSTRAINT auth_challenges_failed_attempts_check CHECK (((failed_attempts >= 0) AND (failed_attempts <= 3)))
);


--
-- Name: equipment_configurations; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.equipment_configurations (
    id uuid DEFAULT uuidv7() NOT NULL,
    category_id uuid NOT NULL,
    policy_id uuid NOT NULL,
    code text NOT NULL,
    allowed boolean DEFAULT false NOT NULL,
    guidance_policy_id uuid
);


--
-- Name: exchanges; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.exchanges (
    id uuid DEFAULT uuidv7() NOT NULL,
    listing_id uuid NOT NULL,
    donor_id uuid NOT NULL,
    requester_id uuid NOT NULL,
    representation_id uuid,
    revision_id uuid NOT NULL,
    state text DEFAULT 'pending'::text NOT NULL,
    paused_reason text,
    requested_loan_days integer,
    proposed_start_date date,
    proposed_end_date date,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    pending_reminder_at timestamp with time zone DEFAULT (now() + '24:00:00'::interval) NOT NULL,
    pending_expires_at timestamp with time zone DEFAULT (now() + '48:00:00'::interval) NOT NULL,
    offered_at timestamp with time zone,
    offer_expires_at timestamp with time zone,
    reserved_at timestamp with time zone,
    closed_at timestamp with time zone,
    closure_reason text,
    idempotency_key uuid NOT NULL,
    retention_ended_at timestamp(6) without time zone,
    retention_end_reason character varying,
    CONSTRAINT exchanges_check CHECK ((donor_id <> requester_id)),
    CONSTRAINT exchanges_check1 CHECK ((pending_reminder_at = (requested_at + '24:00:00'::interval))),
    CONSTRAINT exchanges_check10 CHECK (((proposed_end_date IS NULL) OR ((proposed_start_date IS NOT NULL) AND (proposed_end_date >= proposed_start_date)))),
    CONSTRAINT exchanges_check2 CHECK ((pending_expires_at = (requested_at + '48:00:00'::interval))),
    CONSTRAINT exchanges_check3 CHECK (((offered_at IS NULL) = (offer_expires_at IS NULL))),
    CONSTRAINT exchanges_check4 CHECK ((offer_expires_at = (offered_at + '24:00:00'::interval))),
    CONSTRAINT exchanges_check5 CHECK (((state <> ALL (ARRAY['offered'::text, 'reserved'::text, 'loaned'::text, 'completed'::text])) OR (offered_at IS NOT NULL))),
    CONSTRAINT exchanges_check6 CHECK (((offered_at IS NULL) OR (offered_at >= requested_at))),
    CONSTRAINT exchanges_check7 CHECK (((state <> ALL (ARRAY['reserved'::text, 'loaned'::text, 'completed'::text])) OR (reserved_at IS NOT NULL))),
    CONSTRAINT exchanges_check8 CHECK (((reserved_at IS NULL) OR ((reserved_at >= offered_at) AND (reserved_at < offer_expires_at)))),
    CONSTRAINT exchanges_check9 CHECK (((state = ANY (ARRAY['completed'::text, 'declined'::text, 'expired'::text, 'cancelled'::text, 'closed_unavailable'::text])) = (closed_at IS NOT NULL))),
    CONSTRAINT exchanges_paused_reason_check CHECK ((paused_reason = ANY (ARRAY['delivery_failure'::text, 'opt_out'::text, 'nonresponse'::text, 'security'::text, 'safety'::text]))),
    CONSTRAINT exchanges_requested_loan_days_check CHECK ((requested_loan_days > 0)),
    CONSTRAINT exchanges_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'offered'::text, 'reserved'::text, 'loaned'::text, 'completed'::text, 'declined'::text, 'expired'::text, 'cancelled'::text, 'closed_unavailable'::text]))),
    CONSTRAINT retention_end_complete CHECK (((retention_ended_at IS NULL) = (retention_end_reason IS NULL))),
    CONSTRAINT retention_end_reason_valid CHECK (((retention_end_reason)::text = ANY ((ARRAY['gift_confirmed'::character varying, 'gift_pickup_elapsed'::character varying, 'loan_return_confirmed'::character varying])::text[])))
);


--
-- Name: listing_revisions; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.listing_revisions (
    id uuid DEFAULT uuidv7() NOT NULL,
    listing_id uuid NOT NULL,
    revision_no integer NOT NULL,
    configuration_id uuid NOT NULL,
    service_area_id uuid NOT NULL,
    offer_kind text NOT NULL,
    loan_until date,
    title text NOT NULL,
    description text NOT NULL,
    public_locality text NOT NULL,
    condition_code text NOT NULL,
    condition_description text NOT NULL,
    no_missing_parts_affirmed boolean DEFAULT false NOT NULL,
    fully_functional_affirmed boolean DEFAULT false NOT NULL,
    manufacturer text,
    model text,
    capacity_description text,
    missing_parts text,
    known_defects text,
    modifications text NOT NULL,
    cleaning_status text NOT NULL,
    pickup_availability text NOT NULL,
    free_item_affirmed boolean DEFAULT false NOT NULL,
    truthfulness_affirmed boolean DEFAULT false NOT NULL,
    public_content_checked_at timestamp with time zone,
    submitted_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT listing_revisions_check CHECK ((((offer_kind = 'gift'::text) AND (loan_until IS NULL)) OR ((offer_kind = 'loan'::text) AND (loan_until IS NOT NULL)))),
    CONSTRAINT listing_revisions_check1 CHECK (((loan_until IS NULL) OR (submitted_at IS NULL) OR (loan_until > ((submitted_at AT TIME ZONE 'America/Los_Angeles'::text))::date))),
    CONSTRAINT listing_revisions_condition_code_check CHECK ((condition_code = ANY (ARRAY['new'::text, 'gently_used'::text, 'good'::text, 'requires_repairs'::text]))),
    CONSTRAINT listing_revisions_offer_kind_check CHECK ((offer_kind = ANY (ARRAY['gift'::text, 'loan'::text]))),
    CONSTRAINT listing_revisions_revision_no_check CHECK ((revision_no > 0))
);


--
-- Name: listings; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.listings (
    id uuid DEFAULT uuidv7() NOT NULL,
    donor_id uuid NOT NULL,
    status text DEFAULT 'draft'::text NOT NULL,
    current_revision_id uuid,
    approved_revision_id uuid,
    last_possession_confirmed_at timestamp with time zone,
    availability_valid_until timestamp with time zone,
    allocation_generation integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT listings_allocation_generation_check CHECK ((allocation_generation >= 0)),
    CONSTRAINT listings_status_check CHECK ((status = ANY (ARRAY['draft'::text, 'pending_review'::text, 'available'::text, 'reserved'::text, 'donated'::text, 'loaned'::text, 'unavailable'::text, 'rejected'::text, 'withdrawn'::text])))
);


--
-- Name: restrictions; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.restrictions (
    id uuid DEFAULT uuidv7() NOT NULL,
    listing_id uuid,
    account_id uuid,
    case_id uuid,
    reason text NOT NULL,
    applied_by uuid NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL,
    released_by uuid,
    released_at timestamp with time zone,
    CONSTRAINT restrictions_check CHECK (((((listing_id IS NOT NULL))::integer + ((account_id IS NOT NULL))::integer) = 1)),
    CONSTRAINT restrictions_check1 CHECK (((released_at IS NULL) = (released_by IS NULL))),
    CONSTRAINT restrictions_reason_check CHECK ((reason = ANY (ARRAY['safety'::text, 'recall'::text, 'security'::text, 'policy'::text])))
);


--
-- Name: available_listing_cards; Type: VIEW; Schema: freedme; Owner: -
--

CREATE VIEW freedme.available_listing_cards AS
 SELECT l.id,
    l.donor_id,
    a.display_name,
    r.title,
    r.description,
    c.category_id,
    r.offer_kind,
    r.loan_until,
    r.public_locality,
    r.condition_description,
    r.manufacturer,
    r.model,
    r.capacity_description,
    r.pickup_availability
   FROM (((freedme.listings l
     JOIN freedme.accounts a ON ((a.id = l.donor_id)))
     JOIN freedme.listing_revisions r ON ((r.id = l.approved_revision_id)))
     JOIN freedme.equipment_configurations c ON ((c.id = r.configuration_id)))
  WHERE ((l.status = 'available'::text) AND (l.current_revision_id = l.approved_revision_id) AND (a.status = 'active'::text) AND (l.availability_valid_until > now()) AND c.allowed AND (NOT (EXISTS ( SELECT 1
           FROM freedme.exchanges e
          WHERE ((e.listing_id = l.id) AND (e.state = ANY (ARRAY['pending'::text, 'offered'::text, 'reserved'::text, 'loaned'::text])))))) AND (NOT (EXISTS ( SELECT 1
           FROM freedme.restrictions h
          WHERE ((h.released_at IS NULL) AND ((h.listing_id = l.id) OR (h.account_id = l.donor_id)))))));


--
-- Name: borrower_fields; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.borrower_fields (
    evidence_id uuid NOT NULL,
    field_name text NOT NULL,
    value_ciphertext bytea NOT NULL,
    key_version text NOT NULL,
    source text NOT NULL,
    verification text NOT NULL,
    verified_at timestamp with time zone,
    CONSTRAINT borrower_fields_check CHECK (((verification = 'unverified'::text) OR (verified_at IS NOT NULL))),
    CONSTRAINT borrower_fields_field_name_check CHECK ((field_name = ANY (ARRAY['first_name'::text, 'last_name'::text, 'home_address'::text, 'zip_code'::text]))),
    CONSTRAINT borrower_fields_source_check CHECK ((source = ANY (ARRAY['document'::text, 'user_entered'::text, 'verified_contact'::text]))),
    CONSTRAINT borrower_fields_verification_check CHECK ((verification = ANY (ARRAY['unverified'::text, 'reviewed_against_evidence'::text, 'contact_verified'::text])))
);


--
-- Name: case_actions; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.case_actions (
    id uuid DEFAULT uuidv7() NOT NULL,
    case_id uuid NOT NULL,
    actor_id uuid NOT NULL,
    action text NOT NULL,
    notes_ciphertext bytea,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: cases; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.cases (
    id uuid DEFAULT uuidv7() NOT NULL,
    reporter_id uuid,
    listing_id uuid,
    exchange_id uuid,
    case_type text NOT NULL,
    owner_id uuid NOT NULL,
    severity text NOT NULL,
    state text DEFAULT 'open'::text NOT NULL,
    details_ciphertext bytea,
    next_action text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    acknowledged_at timestamp with time zone,
    closed_at timestamp with time zone,
    closure_reason text,
    CONSTRAINT cases_case_type_check CHECK ((case_type = ANY (ARRAY['unsafe'::text, 'recall'::text, 'payment_demand'::text, 'harassment'::text, 'privacy'::text, 'failed_pickup'::text, 'non_return'::text, 'transport'::text, 'recovery'::text, 'help'::text]))),
    CONSTRAINT cases_severity_check CHECK ((severity = ANY (ARRAY['urgent'::text, 'standard'::text]))),
    CONSTRAINT cases_state_check CHECK ((state = ANY (ARRAY['open'::text, 'acknowledged'::text, 'investigating'::text, 'resolved'::text, 'closed'::text])))
);


--
-- Name: categories; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.categories (
    id uuid DEFAULT uuidv7() NOT NULL,
    code text NOT NULL,
    name text NOT NULL
);


--
-- Name: consent_events; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.consent_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    account_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    purpose text NOT NULL,
    action text NOT NULL,
    policy_id uuid,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    idempotency_key text NOT NULL,
    CONSTRAINT consent_events_action_check CHECK ((action = ANY (ARRAY['granted'::text, 'withdrawn'::text, 'stop'::text, 'reset'::text]))),
    CONSTRAINT consent_events_purpose_check CHECK ((purpose = ANY (ARRAY['otp'::text, 'routine_sms'::text, 'email_notifications'::text, 'email_marketing'::text])))
);


--
-- Name: handoff_acceptances; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.handoff_acceptances (
    proposal_id uuid NOT NULL,
    exchange_id uuid NOT NULL,
    accepted_by uuid NOT NULL,
    accepted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: handoff_proposals; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.handoff_proposals (
    id uuid DEFAULT uuidv7() NOT NULL,
    exchange_id uuid NOT NULL,
    revision integer NOT NULL,
    proposed_by uuid NOT NULL,
    meeting_at timestamp with time zone NOT NULL,
    display_timezone text DEFAULT 'America/Los_Angeles'::text NOT NULL,
    public_location_ciphertext bytea NOT NULL,
    key_version text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    idempotency_key uuid NOT NULL,
    CONSTRAINT handoff_proposals_revision_check CHECK ((revision > 0))
);


--
-- Name: current_handoff_arrangements; Type: VIEW; Schema: freedme; Owner: -
--

CREATE VIEW freedme.current_handoff_arrangements AS
 SELECT DISTINCT ON (p.exchange_id) p.id,
    p.exchange_id,
    p.revision,
    p.proposed_by,
    p.meeting_at,
    p.display_timezone,
    p.public_location_ciphertext,
    p.key_version,
    p.created_at,
    p.idempotency_key,
    a.accepted_by,
    a.accepted_at
   FROM (freedme.handoff_proposals p
     LEFT JOIN freedme.handoff_acceptances a ON ((a.proposal_id = p.id)))
  ORDER BY p.exchange_id, p.revision DESC;


--
-- Name: deletion_jobs; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.deletion_jobs (
    id uuid DEFAULT uuidv7() NOT NULL,
    rule_id uuid NOT NULL,
    record_id uuid NOT NULL,
    due_at timestamp with time zone NOT NULL,
    state text DEFAULT 'queued'::text NOT NULL,
    completed_at timestamp with time zone,
    proof_digest text,
    idempotency_key text NOT NULL,
    CONSTRAINT deletion_jobs_state_check CHECK ((state = ANY (ARRAY['queued'::text, 'held'::text, 'running'::text, 'complete'::text, 'failed'::text])))
);


--
-- Name: disclosure_grants; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.disclosure_grants (
    id uuid DEFAULT uuidv7() NOT NULL,
    exchange_id uuid NOT NULL,
    evidence_id uuid NOT NULL,
    consented_by uuid NOT NULL,
    donor_id uuid NOT NULL,
    consent_policy_id uuid NOT NULL,
    allowed_fields text[] NOT NULL,
    granted_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT disclosure_grants_allowed_fields_check CHECK (((cardinality(allowed_fields) > 0) AND (allowed_fields <@ ARRAY['first_name'::text, 'last_name'::text, 'zip_code'::text]))),
    CONSTRAINT disclosure_grants_check CHECK ((expires_at > granted_at))
);


--
-- Name: equipment_questions; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.equipment_questions (
    id uuid DEFAULT uuidv7() NOT NULL,
    listing_id uuid NOT NULL,
    donor_id uuid NOT NULL,
    requester_id uuid NOT NULL,
    question_ciphertext bytea NOT NULL,
    answer_ciphertext bytea,
    key_version text NOT NULL,
    state text DEFAULT 'pending'::text NOT NULL,
    asked_at timestamp with time zone DEFAULT now() NOT NULL,
    answered_at timestamp with time zone,
    answered_by uuid,
    idempotency_key uuid NOT NULL,
    archived_at timestamp(6) without time zone,
    CONSTRAINT equipment_questions_check CHECK ((requester_id <> donor_id)),
    CONSTRAINT equipment_questions_check1 CHECK (((state = 'answered'::text) = (answer_ciphertext IS NOT NULL))),
    CONSTRAINT equipment_questions_check2 CHECK (((answer_ciphertext IS NULL) = (answered_at IS NULL))),
    CONSTRAINT equipment_questions_check3 CHECK (((answer_ciphertext IS NULL) = (answered_by IS NULL))),
    CONSTRAINT equipment_questions_check4 CHECK (((answered_by IS NULL) OR (answered_by = donor_id))),
    CONSTRAINT equipment_questions_check5 CHECK (((answered_at IS NULL) OR (answered_at >= asked_at))),
    CONSTRAINT equipment_questions_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'answered'::text, 'withdrawn'::text])))
);


--
-- Name: exchange_display_preferences; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.exchange_display_preferences (
    exchange_id uuid NOT NULL,
    account_id uuid NOT NULL,
    hidden_at timestamp with time zone,
    replaced_by_exchange_id uuid,
    CONSTRAINT exchange_display_preferences_check CHECK ((replaced_by_exchange_id IS DISTINCT FROM exchange_id))
);


--
-- Name: exchange_events; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.exchange_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    exchange_id uuid NOT NULL,
    actor_id uuid,
    event_type text NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    reason_code text,
    idempotency_key uuid NOT NULL,
    CONSTRAINT exchange_events_event_type_check CHECK ((event_type = ANY (ARRAY['requested'::text, 'offered'::text, 'reserved'::text, 'cancelled'::text, 'declined'::text, 'expired'::text, 'handoff_confirmed'::text, 'return_reported'::text, 'return_confirmed'::text, 'possession_confirmed'::text, 'reopened'::text, 'unavailable'::text, 'extension_reported'::text, 'paused'::text, 'resumed'::text])))
);


--
-- Name: followup_cycles; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.followup_cycles (
    id uuid DEFAULT uuidv7() NOT NULL,
    exchange_id uuid NOT NULL,
    kind text NOT NULL,
    state text DEFAULT 'pending'::text NOT NULL,
    next_due_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT followup_cycles_kind_check CHECK ((kind = ANY (ARRAY['handoff'::text, 'return'::text]))),
    CONSTRAINT followup_cycles_state_check CHECK ((state = ANY (ARRAY['pending'::text, 'cancelled'::text, 'answered'::text, 'moderator_action_due'::text, 'closed'::text])))
);


--
-- Name: gateway_events; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.gateway_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    provider text NOT NULL,
    provider_event_id text NOT NULL,
    attempt_id uuid,
    event_type text NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone
);


--
-- Name: identity_document_uploads; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.identity_document_uploads (
    id uuid DEFAULT uuidv7() NOT NULL,
    account_id uuid NOT NULL,
    listing_id uuid NOT NULL,
    revision_id uuid NOT NULL,
    exchange_id uuid,
    document_kind character varying NOT NULL,
    state character varying DEFAULT 'processing'::character varying NOT NULL,
    image_ciphertext bytea,
    fields_ciphertext bytea,
    purge_due_at timestamp(6) without time zone NOT NULL,
    image_deleted_at timestamp(6) without time zone,
    confirmed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT identity_upload_kind CHECK (((document_kind)::text = ANY ((ARRAY['utility_bill'::character varying, 'government_id'::character varying])::text[]))),
    CONSTRAINT identity_upload_state CHECK (((state)::text = ANY ((ARRAY['processing'::character varying, 'extracted'::character varying, 'failed'::character varying, 'confirmed'::character varying])::text[])))
);


--
-- Name: identity_evidence; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.identity_evidence (
    id uuid DEFAULT uuidv7() NOT NULL,
    submitted_by uuid NOT NULL,
    representation_id uuid,
    document_kind text NOT NULL,
    restricted_object_key text,
    review_state text DEFAULT 'pending'::text NOT NULL,
    reviewer_id uuid,
    verification_provider text,
    provider_reference text,
    reviewed_at timestamp with time zone,
    valid_until timestamp with time zone,
    policy_id uuid NOT NULL,
    replaces_evidence_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    purge_due_at timestamp with time zone,
    deleted_at timestamp with time zone,
    CONSTRAINT identity_evidence_check CHECK (((review_state <> 'approved'::text) OR (((reviewer_id IS NOT NULL) OR (verification_provider IS NOT NULL)) AND (reviewed_at IS NOT NULL) AND (valid_until IS NOT NULL) AND (valid_until > reviewed_at)))),
    CONSTRAINT identity_evidence_document_kind_check CHECK ((document_kind = ANY (ARRAY['utility_bill'::text, 'government_id'::text]))),
    CONSTRAINT identity_evidence_review_state_check CHECK ((review_state = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'revoked'::text, 'deleted'::text])))
);


--
-- Name: listing_photos; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.listing_photos (
    id uuid DEFAULT uuidv7() NOT NULL,
    revision_id uuid NOT NULL,
    slot smallint NOT NULL,
    original_object_key text,
    sanitized_object_key text,
    mime_type text NOT NULL,
    byte_size integer NOT NULL,
    metadata_stripped_at timestamp with time zone,
    content_reviewed_at timestamp with time zone,
    state text DEFAULT 'processing'::text NOT NULL,
    CONSTRAINT listing_photos_byte_size_check CHECK (((byte_size > 0) AND (byte_size <= 5242880))),
    CONSTRAINT listing_photos_check CHECK (((state <> 'approved'::text) OR ((sanitized_object_key IS NOT NULL) AND (metadata_stripped_at IS NOT NULL) AND (content_reviewed_at IS NOT NULL)))),
    CONSTRAINT listing_photos_mime_type_check CHECK ((mime_type = ANY (ARRAY['image/jpeg'::text, 'image/png'::text]))),
    CONSTRAINT listing_photos_slot_check CHECK (((slot >= 1) AND (slot <= 5))),
    CONSTRAINT listing_photos_state_check CHECK ((state = ANY (ARRAY['processing'::text, 'approved'::text, 'rejected'::text])))
);


--
-- Name: listing_review_alerts; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.listing_review_alerts (
    id bigint NOT NULL,
    account_id uuid NOT NULL,
    revision_id uuid NOT NULL,
    email_state character varying DEFAULT 'queued'::character varying NOT NULL,
    sms_state character varying DEFAULT 'queued'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: listing_review_alerts_id_seq; Type: SEQUENCE; Schema: freedme; Owner: -
--

CREATE SEQUENCE freedme.listing_review_alerts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: listing_review_alerts_id_seq; Type: SEQUENCE OWNED BY; Schema: freedme; Owner: -
--

ALTER SEQUENCE freedme.listing_review_alerts_id_seq OWNED BY freedme.listing_review_alerts.id;


--
-- Name: listing_reviews; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.listing_reviews (
    id uuid DEFAULT uuidv7() NOT NULL,
    revision_id uuid NOT NULL,
    reviewer_id uuid NOT NULL,
    decision text NOT NULL,
    disclosures_checked boolean NOT NULL,
    recall_checked boolean NOT NULL,
    reason text NOT NULL,
    reviewed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT listing_reviews_decision_check CHECK ((decision = ANY (ARRAY['approved'::text, 'changes_requested'::text, 'rejected'::text])))
);


--
-- Name: loan_terms_history; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.loan_terms_history (
    id uuid DEFAULT uuidv7() NOT NULL,
    exchange_id uuid NOT NULL,
    reported_by uuid NOT NULL,
    starts_at timestamp with time zone,
    due_at timestamp with time zone,
    reason text NOT NULL,
    timing_policy_id uuid NOT NULL,
    reported_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT loan_terms_history_check CHECK (((due_at IS NULL) OR ((starts_at IS NOT NULL) AND (due_at > starts_at)))),
    CONSTRAINT loan_terms_history_reason_check CHECK ((reason = ANY (ARRAY['initial'::text, 'extension'::text, 'early_return'::text])))
);


--
-- Name: message_attempts; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.message_attempts (
    id uuid DEFAULT uuidv7() NOT NULL,
    job_id uuid NOT NULL,
    attempt_no integer NOT NULL,
    provider text NOT NULL,
    provider_message_id text,
    state text NOT NULL,
    error_code text,
    attempted_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT message_attempts_attempt_no_check CHECK ((attempt_no > 0)),
    CONSTRAINT message_attempts_state_check CHECK ((state = ANY (ARRAY['sending'::text, 'accepted'::text, 'delivered'::text, 'failed'::text, 'unknown'::text])))
);


--
-- Name: message_jobs; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.message_jobs (
    id uuid DEFAULT uuidv7() NOT NULL,
    recipient_id uuid NOT NULL,
    contact_id uuid NOT NULL,
    exchange_id uuid,
    followup_cycle_id uuid,
    followup_attempt smallint,
    template_code text NOT NULL,
    state text DEFAULT 'queued'::text NOT NULL,
    due_at timestamp with time zone NOT NULL,
    claimed_until timestamp with time zone,
    sent_at timestamp with time zone,
    idempotency_key text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    question_id uuid,
    listing_id uuid,
    template_version integer DEFAULT 1 NOT NULL,
    CONSTRAINT message_jobs_check CHECK (((followup_cycle_id IS NULL) = (followup_attempt IS NULL))),
    CONSTRAINT message_jobs_followup_attempt_check CHECK (((followup_attempt >= 1) AND (followup_attempt <= 3))),
    CONSTRAINT message_jobs_state_check CHECK ((state = ANY (ARRAY['queued'::text, 'claimed'::text, 'sent'::text, 'failed'::text, 'cancelled'::text, 'suppressed'::text])))
);


--
-- Name: moderator_tasks; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.moderator_tasks (
    id uuid DEFAULT uuidv7() NOT NULL,
    exchange_id uuid NOT NULL,
    kind text NOT NULL,
    due_at timestamp with time zone NOT NULL,
    state text DEFAULT 'open'::text NOT NULL,
    assigned_to uuid,
    donor_contacted_at timestamp with time zone,
    recipient_contacted_at timestamp with time zone,
    outcome text,
    notes_ciphertext bytea,
    resolved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT moderator_tasks_check CHECK (((state = ANY (ARRAY['resolved'::text, 'cancelled'::text])) = (resolved_at IS NOT NULL))),
    CONSTRAINT moderator_tasks_check1 CHECK (((state <> 'resolved'::text) OR (outcome IS NOT NULL))),
    CONSTRAINT moderator_tasks_kind_check CHECK ((kind = 'unconfirmed_handoff'::text)),
    CONSTRAINT moderator_tasks_outcome_check CHECK ((outcome = ANY (ARRAY['handoff_confirmed'::text, 'not_handed_off'::text, 'unable_to_reach'::text, 'cancelled'::text]))),
    CONSTRAINT moderator_tasks_state_check CHECK ((state = ANY (ARRAY['open'::text, 'in_progress'::text, 'resolved'::text, 'cancelled'::text])))
);


--
-- Name: notification_templates; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.notification_templates (
    code text NOT NULL,
    version integer NOT NULL,
    body text NOT NULL,
    approved_at timestamp with time zone,
    CONSTRAINT notification_templates_version_check CHECK ((version > 0))
);


--
-- Name: organization_participation; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.organization_participation (
    id uuid DEFAULT uuidv7() NOT NULL,
    organization_name text NOT NULL,
    agreed_role text NOT NULL,
    contact_ciphertext bytea,
    agreed_at timestamp with time zone NOT NULL,
    ended_at timestamp with time zone,
    public_listing_permission boolean DEFAULT false NOT NULL
);


--
-- Name: photo_screenings; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.photo_screenings (
    id uuid DEFAULT uuidv7() NOT NULL,
    account_id uuid NOT NULL,
    image_digest character varying NOT NULL,
    policy_key character varying NOT NULL,
    state character varying DEFAULT 'unavailable'::character varying NOT NULL,
    labels jsonb DEFAULT '[]'::jsonb NOT NULL,
    model_version character varying,
    attempts integer DEFAULT 0 NOT NULL,
    last_attempt_at timestamp(6) without time zone,
    checked_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    CONSTRAINT photo_screening_state CHECK (((state)::text = ANY ((ARRAY['accepted'::character varying, 'needs_review'::character varying, 'rejected'::character varying, 'unavailable'::character varying])::text[])))
);


--
-- Name: pilot_controls; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.pilot_controls (
    singleton boolean DEFAULT true NOT NULL,
    loans_enabled boolean DEFAULT false NOT NULL,
    evidence_collection_enabled boolean DEFAULT false NOT NULL,
    privacy_policy_id uuid,
    loan_policy_id uuid,
    CONSTRAINT pilot_controls_check CHECK (((NOT evidence_collection_enabled) OR (privacy_policy_id IS NOT NULL))),
    CONSTRAINT pilot_controls_check1 CHECK (((NOT loans_enabled) OR (evidence_collection_enabled AND (loan_policy_id IS NOT NULL)))),
    CONSTRAINT pilot_controls_singleton_check CHECK (singleton)
);


--
-- Name: policy_acknowledgments; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.policy_acknowledgments (
    id uuid DEFAULT uuidv7() NOT NULL,
    account_id uuid NOT NULL,
    policy_id uuid NOT NULL,
    listing_id uuid,
    exchange_id uuid,
    purpose text NOT NULL,
    accepted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: policy_versions; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.policy_versions (
    id uuid DEFAULT uuidv7() NOT NULL,
    kind text NOT NULL,
    version text NOT NULL,
    content_sha256 text NOT NULL,
    content_object_key text NOT NULL,
    configuration jsonb DEFAULT '{}'::jsonb NOT NULL,
    approved_by uuid,
    approved_at timestamp with time zone,
    effective_at timestamp with time zone,
    CONSTRAINT policy_versions_check CHECK (((approved_at IS NULL) = (approved_by IS NULL)))
);


--
-- Name: privacy_deletion_requests; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.privacy_deletion_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_id uuid NOT NULL,
    state character varying DEFAULT 'pending_review'::character varying NOT NULL,
    requested_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT privacy_request_state CHECK (((state)::text = ANY ((ARRAY['pending_review'::character varying, 'reviewing'::character varying])::text[])))
);


--
-- Name: private_messages; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.private_messages (
    id uuid DEFAULT uuidv7() NOT NULL,
    exchange_id uuid NOT NULL,
    sender_id uuid NOT NULL,
    recipient_id uuid NOT NULL,
    body_ciphertext bytea NOT NULL,
    key_version text NOT NULL,
    state text DEFAULT 'draft'::text NOT NULL,
    messaging_policy_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT private_messages_check CHECK ((sender_id <> recipient_id)),
    CONSTRAINT private_messages_check1 CHECK (((state = 'draft'::text) OR (messaging_policy_id IS NOT NULL))),
    CONSTRAINT private_messages_state_check CHECK ((state = ANY (ARRAY['draft'::text, 'queued'::text, 'sent'::text, 'failed'::text, 'received'::text])))
);


--
-- Name: recall_reviews; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.recall_reviews (
    id uuid DEFAULT uuidv7() NOT NULL,
    revision_id uuid NOT NULL,
    reviewer_id uuid NOT NULL,
    source_url text NOT NULL,
    product_identification text NOT NULL,
    result text NOT NULL,
    notes_ciphertext bytea,
    policy_id uuid NOT NULL,
    reviewed_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT recall_reviews_result_check CHECK ((result = ANY (ARRAY['no_match'::text, 'potential_match'::text, 'confirmed_unresolved'::text, 'insufficient_identification'::text, 'resolved_under_policy'::text])))
);


--
-- Name: registration_sessions; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.registration_sessions (
    id uuid DEFAULT uuidv7() NOT NULL,
    challenge_id uuid NOT NULL,
    display_name text NOT NULL,
    approximate_location text NOT NULL,
    intended_action text NOT NULL,
    listing_id uuid,
    created_account_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    CONSTRAINT registration_sessions_approximate_location_check CHECK (((length(TRIM(BOTH FROM approximate_location)) >= 1) AND (length(TRIM(BOTH FROM approximate_location)) <= 160))),
    CONSTRAINT registration_sessions_check CHECK ((expires_at > created_at)),
    CONSTRAINT registration_sessions_check1 CHECK (((intended_action <> 'request'::text) OR (listing_id IS NOT NULL))),
    CONSTRAINT registration_sessions_display_name_check CHECK (((length(TRIM(BOTH FROM display_name)) >= 1) AND (length(TRIM(BOTH FROM display_name)) <= 80))),
    CONSTRAINT registration_sessions_intended_action_check CHECK ((intended_action = ANY (ARRAY['donate'::text, 'request'::text])))
);


--
-- Name: reporting_archives; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.reporting_archives (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    exchange_id uuid,
    listing_id uuid NOT NULL,
    category_code character varying NOT NULL,
    offer_kind character varying NOT NULL,
    outcome character varying NOT NULL,
    archived_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: representations; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.representations (
    id uuid DEFAULT uuidv7() NOT NULL,
    representative_id uuid NOT NULL,
    recipient_account_id uuid,
    relationship text NOT NULL,
    subject_reference_ciphertext bytea,
    authority_policy_id uuid NOT NULL,
    authorized_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    CONSTRAINT representations_relationship_check CHECK ((relationship = ANY (ARRAY['caregiver'::text, 'family'::text, 'community_helper'::text])))
);


--
-- Name: request_intents; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.request_intents (
    id uuid DEFAULT uuidv7() NOT NULL,
    listing_id uuid NOT NULL,
    requester_id uuid NOT NULL,
    representation_id uuid,
    evidence_id uuid,
    state text DEFAULT 'awaiting_evidence'::text NOT NULL,
    exchange_id uuid,
    requested_end_date date,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    idempotency_key uuid NOT NULL,
    CONSTRAINT request_intents_check CHECK ((expires_at > created_at)),
    CONSTRAINT request_intents_check1 CHECK (((state = 'submitted'::text) = (exchange_id IS NOT NULL))),
    CONSTRAINT request_intents_state_check CHECK ((state = ANY (ARRAY['awaiting_evidence'::text, 'verifying'::text, 'failed'::text, 'verified'::text, 'submitted'::text, 'cancelled'::text, 'expired'::text])))
);


--
-- Name: reservation_facts; Type: VIEW; Schema: freedme; Owner: -
--

CREATE VIEW freedme.reservation_facts AS
 SELECT id AS exchange_id,
    listing_id,
    requester_id,
    representation_id,
    reserved_at,
    ((reserved_at IS NOT NULL) AND (state <> ALL (ARRAY['cancelled'::text, 'closed_unavailable'::text]))) AS counts_as_success,
    ( SELECT min(v.occurred_at) AS min
           FROM freedme.exchange_events v
          WHERE ((v.exchange_id = e.id) AND (v.event_type = 'handoff_confirmed'::text))) AS handoff_confirmed_at,
    ( SELECT min(v.occurred_at) AS min
           FROM freedme.exchange_events v
          WHERE ((v.exchange_id = e.id) AND (v.event_type = 'return_confirmed'::text))) AS return_confirmed_at
   FROM freedme.exchanges e
  WHERE (reserved_at IS NOT NULL);


--
-- Name: resources; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.resources (
    id uuid DEFAULT uuidv7() NOT NULL,
    name text NOT NULL,
    service_type text NOT NULL,
    service_area text NOT NULL,
    cost_model text NOT NULL,
    restrictions text,
    official_url text NOT NULL,
    official_contact text,
    reviewer_id uuid,
    verification_provider text,
    provider_reference text,
    reviewed_at timestamp with time zone,
    published boolean DEFAULT false NOT NULL,
    CONSTRAINT resources_check CHECK (((NOT published) OR ((reviewer_id IS NOT NULL) AND (reviewed_at IS NOT NULL)))),
    CONSTRAINT resources_service_type_check CHECK ((service_type = ANY (ARRAY['donation'::text, 'loan'::text, 'mixed_exchange'::text, 'referral_only'::text])))
);


--
-- Name: retention_holds; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.retention_holds (
    id uuid DEFAULT uuidv7() NOT NULL,
    case_id uuid NOT NULL,
    data_class text NOT NULL,
    record_id uuid NOT NULL,
    created_by uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    released_at timestamp with time zone
);


--
-- Name: retention_rules; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.retention_rules (
    id uuid DEFAULT uuidv7() NOT NULL,
    data_class text NOT NULL,
    policy_id uuid NOT NULL,
    trigger_event text NOT NULL,
    retain_for interval NOT NULL,
    CONSTRAINT retention_rules_retain_for_check CHECK ((retain_for >= '00:00:00'::interval))
);


--
-- Name: sensitive_access_events; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.sensitive_access_events (
    id uuid DEFAULT uuidv7() NOT NULL,
    actor_id uuid NOT NULL,
    grant_id uuid,
    evidence_id uuid,
    purpose text NOT NULL,
    allowed boolean NOT NULL,
    field_names text[] DEFAULT '{}'::text[] NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: service_areas; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.service_areas (
    id uuid DEFAULT uuidv7() NOT NULL,
    policy_id uuid NOT NULL,
    zip_code text NOT NULL,
    county text NOT NULL,
    city text NOT NULL,
    centroid_lat numeric(9,6),
    centroid_lon numeric(9,6),
    donor_eligible boolean DEFAULT false NOT NULL,
    recipient_eligible boolean DEFAULT false NOT NULL,
    CONSTRAINT service_areas_centroid_lat_check CHECK (((centroid_lat >= ('-90'::integer)::numeric) AND (centroid_lat <= (90)::numeric))),
    CONSTRAINT service_areas_centroid_lon_check CHECK (((centroid_lon >= ('-180'::integer)::numeric) AND (centroid_lon <= (180)::numeric))),
    CONSTRAINT service_areas_zip_code_check CHECK ((zip_code ~ '^[0-9]{5}$'::text))
);


--
-- Name: simulated_sms_messages; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.simulated_sms_messages (
    id uuid DEFAULT uuidv7() NOT NULL,
    recipient character varying NOT NULL,
    template_code character varying NOT NULL,
    body text NOT NULL,
    idempotency_key character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    recipient_account_id uuid
);


--
-- Name: sms_deliveries; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.sms_deliveries (
    id uuid DEFAULT uuidv7() NOT NULL,
    recipient_ciphertext text NOT NULL,
    recipient_hmac bytea NOT NULL,
    body_ciphertext text NOT NULL,
    template_code character varying NOT NULL,
    idempotency_key character varying NOT NULL,
    state character varying DEFAULT 'queued'::character varying NOT NULL,
    provider_sid character varying,
    delivery_status character varying,
    error_code character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    recipient_account_id uuid,
    CONSTRAINT sms_delivery_state CHECK (((state)::text = ANY ((ARRAY['queued'::character varying, 'sending'::character varying, 'accepted'::character varying, 'failed'::character varying, 'suppressed'::character varying])::text[])))
);


--
-- Name: staff_credentials; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.staff_credentials (
    account_id uuid NOT NULL,
    first_name_ciphertext bytea NOT NULL,
    last_name_ciphertext bytea NOT NULL,
    email_contact_id uuid NOT NULL,
    password_digest text NOT NULL,
    mfa_secret_ciphertext bytea NOT NULL,
    mfa_enrolled_at timestamp with time zone,
    key_version text NOT NULL,
    username character varying,
    failed_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp(6) without time zone,
    last_totp_at bigint,
    session_version character varying DEFAULT ''::character varying NOT NULL
);


--
-- Name: team_profiles; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.team_profiles (
    id uuid DEFAULT uuidv7() NOT NULL,
    display_name text NOT NULL,
    role_title text NOT NULL,
    biography text NOT NULL,
    photo_object_key text,
    sort_order integer DEFAULT 0 NOT NULL,
    publication_consent_at timestamp with time zone,
    published_at timestamp with time zone,
    CONSTRAINT team_profiles_check CHECK (((published_at IS NULL) OR (publication_consent_at IS NOT NULL)))
);


--
-- Name: transport_barriers; Type: TABLE; Schema: freedme; Owner: -
--

CREATE TABLE freedme.transport_barriers (
    id uuid DEFAULT uuidv7() NOT NULL,
    exchange_id uuid NOT NULL,
    reported_by uuid NOT NULL,
    stage text NOT NULL,
    reason text NOT NULL,
    resource_id uuid,
    recorded_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT transport_barriers_reason_check CHECK ((reason = ANY (ARRAY['no_transport'::text, 'accessibility'::text, 'schedule'::text, 'other'::text]))),
    CONSTRAINT transport_barriers_stage_check CHECK ((stage = ANY (ARRAY['before_reservation'::text, 'after_reservation'::text])))
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
-- Name: listing_review_alerts id; Type: DEFAULT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_review_alerts ALTER COLUMN id SET DEFAULT nextval('freedme.listing_review_alerts_id_seq'::regclass);


--
-- Name: account_contacts account_contacts_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.account_contacts
    ADD CONSTRAINT account_contacts_pkey PRIMARY KEY (id);


--
-- Name: account_notices account_notices_idempotency_key_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.account_notices
    ADD CONSTRAINT account_notices_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: account_notices account_notices_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.account_notices
    ADD CONSTRAINT account_notices_pkey PRIMARY KEY (id);


--
-- Name: account_roles account_roles_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.account_roles
    ADD CONSTRAINT account_roles_pkey PRIMARY KEY (account_id, role);


--
-- Name: accounts accounts_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.accounts
    ADD CONSTRAINT accounts_pkey PRIMARY KEY (id);


--
-- Name: action_tokens action_tokens_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.action_tokens
    ADD CONSTRAINT action_tokens_pkey PRIMARY KEY (id);


--
-- Name: action_tokens action_tokens_token_digest_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.action_tokens
    ADD CONSTRAINT action_tokens_token_digest_key UNIQUE (token_digest);


--
-- Name: activity_events activity_events_idempotency_key_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.activity_events
    ADD CONSTRAINT activity_events_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: activity_events activity_events_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.activity_events
    ADD CONSTRAINT activity_events_pkey PRIMARY KEY (id);


--
-- Name: agreements agreements_exchange_id_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.agreements
    ADD CONSTRAINT agreements_exchange_id_key UNIQUE (exchange_id);


--
-- Name: agreements agreements_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.agreements
    ADD CONSTRAINT agreements_pkey PRIMARY KEY (id);


--
-- Name: audit_events audit_events_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.audit_events
    ADD CONSTRAINT audit_events_pkey PRIMARY KEY (id);


--
-- Name: auth_challenges auth_challenges_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.auth_challenges
    ADD CONSTRAINT auth_challenges_pkey PRIMARY KEY (id);


--
-- Name: borrower_fields borrower_fields_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.borrower_fields
    ADD CONSTRAINT borrower_fields_pkey PRIMARY KEY (evidence_id, field_name);


--
-- Name: case_actions case_actions_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.case_actions
    ADD CONSTRAINT case_actions_pkey PRIMARY KEY (id);


--
-- Name: cases cases_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.cases
    ADD CONSTRAINT cases_pkey PRIMARY KEY (id);


--
-- Name: categories categories_code_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.categories
    ADD CONSTRAINT categories_code_key UNIQUE (code);


--
-- Name: categories categories_name_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.categories
    ADD CONSTRAINT categories_name_key UNIQUE (name);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: consent_events consent_events_idempotency_key_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.consent_events
    ADD CONSTRAINT consent_events_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: consent_events consent_events_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.consent_events
    ADD CONSTRAINT consent_events_pkey PRIMARY KEY (id);


--
-- Name: deletion_jobs deletion_jobs_idempotency_key_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.deletion_jobs
    ADD CONSTRAINT deletion_jobs_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: deletion_jobs deletion_jobs_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.deletion_jobs
    ADD CONSTRAINT deletion_jobs_pkey PRIMARY KEY (id);


--
-- Name: disclosure_grants disclosure_grants_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.disclosure_grants
    ADD CONSTRAINT disclosure_grants_pkey PRIMARY KEY (id);


--
-- Name: equipment_configurations equipment_configurations_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.equipment_configurations
    ADD CONSTRAINT equipment_configurations_pkey PRIMARY KEY (id);


--
-- Name: equipment_configurations equipment_configurations_policy_id_category_id_code_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.equipment_configurations
    ADD CONSTRAINT equipment_configurations_policy_id_category_id_code_key UNIQUE (policy_id, category_id, code);


--
-- Name: equipment_questions equipment_questions_idempotency_key_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.equipment_questions
    ADD CONSTRAINT equipment_questions_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: equipment_questions equipment_questions_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.equipment_questions
    ADD CONSTRAINT equipment_questions_pkey PRIMARY KEY (id);


--
-- Name: exchange_display_preferences exchange_display_preferences_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchange_display_preferences
    ADD CONSTRAINT exchange_display_preferences_pkey PRIMARY KEY (exchange_id, account_id);


--
-- Name: exchange_events exchange_events_idempotency_key_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchange_events
    ADD CONSTRAINT exchange_events_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: exchange_events exchange_events_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchange_events
    ADD CONSTRAINT exchange_events_pkey PRIMARY KEY (id);


--
-- Name: exchanges exchanges_id_listing_id_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchanges
    ADD CONSTRAINT exchanges_id_listing_id_key UNIQUE (id, listing_id);


--
-- Name: exchanges exchanges_idempotency_key_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchanges
    ADD CONSTRAINT exchanges_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: exchanges exchanges_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchanges
    ADD CONSTRAINT exchanges_pkey PRIMARY KEY (id);


--
-- Name: followup_cycles followup_cycles_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.followup_cycles
    ADD CONSTRAINT followup_cycles_pkey PRIMARY KEY (id);


--
-- Name: gateway_events gateway_events_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.gateway_events
    ADD CONSTRAINT gateway_events_pkey PRIMARY KEY (id);


--
-- Name: gateway_events gateway_events_provider_provider_event_id_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.gateway_events
    ADD CONSTRAINT gateway_events_provider_provider_event_id_key UNIQUE (provider, provider_event_id);


--
-- Name: handoff_acceptances handoff_acceptances_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.handoff_acceptances
    ADD CONSTRAINT handoff_acceptances_pkey PRIMARY KEY (proposal_id);


--
-- Name: handoff_proposals handoff_proposals_exchange_id_revision_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.handoff_proposals
    ADD CONSTRAINT handoff_proposals_exchange_id_revision_key UNIQUE (exchange_id, revision);


--
-- Name: handoff_proposals handoff_proposals_id_exchange_id_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.handoff_proposals
    ADD CONSTRAINT handoff_proposals_id_exchange_id_key UNIQUE (id, exchange_id);


--
-- Name: handoff_proposals handoff_proposals_idempotency_key_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.handoff_proposals
    ADD CONSTRAINT handoff_proposals_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: handoff_proposals handoff_proposals_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.handoff_proposals
    ADD CONSTRAINT handoff_proposals_pkey PRIMARY KEY (id);


--
-- Name: identity_document_uploads identity_document_uploads_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_document_uploads
    ADD CONSTRAINT identity_document_uploads_pkey PRIMARY KEY (id);


--
-- Name: identity_evidence identity_evidence_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_evidence
    ADD CONSTRAINT identity_evidence_pkey PRIMARY KEY (id);


--
-- Name: listing_photos listing_photos_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_photos
    ADD CONSTRAINT listing_photos_pkey PRIMARY KEY (id);


--
-- Name: listing_photos listing_photos_revision_id_slot_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_photos
    ADD CONSTRAINT listing_photos_revision_id_slot_key UNIQUE (revision_id, slot);


--
-- Name: listing_review_alerts listing_review_alerts_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_review_alerts
    ADD CONSTRAINT listing_review_alerts_pkey PRIMARY KEY (id);


--
-- Name: listing_reviews listing_reviews_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_reviews
    ADD CONSTRAINT listing_reviews_pkey PRIMARY KEY (id);


--
-- Name: listing_revisions listing_revisions_listing_id_id_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_revisions
    ADD CONSTRAINT listing_revisions_listing_id_id_key UNIQUE (listing_id, id);


--
-- Name: listing_revisions listing_revisions_listing_id_revision_no_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_revisions
    ADD CONSTRAINT listing_revisions_listing_id_revision_no_key UNIQUE (listing_id, revision_no);


--
-- Name: listing_revisions listing_revisions_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_revisions
    ADD CONSTRAINT listing_revisions_pkey PRIMARY KEY (id);


--
-- Name: listings listings_id_donor_id_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listings
    ADD CONSTRAINT listings_id_donor_id_key UNIQUE (id, donor_id);


--
-- Name: listings listings_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listings
    ADD CONSTRAINT listings_pkey PRIMARY KEY (id);


--
-- Name: loan_terms_history loan_terms_history_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.loan_terms_history
    ADD CONSTRAINT loan_terms_history_pkey PRIMARY KEY (id);


--
-- Name: message_attempts message_attempts_job_id_attempt_no_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_attempts
    ADD CONSTRAINT message_attempts_job_id_attempt_no_key UNIQUE (job_id, attempt_no);


--
-- Name: message_attempts message_attempts_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_attempts
    ADD CONSTRAINT message_attempts_pkey PRIMARY KEY (id);


--
-- Name: message_attempts message_attempts_provider_provider_message_id_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_attempts
    ADD CONSTRAINT message_attempts_provider_provider_message_id_key UNIQUE (provider, provider_message_id);


--
-- Name: message_jobs message_jobs_followup_cycle_id_followup_attempt_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_jobs
    ADD CONSTRAINT message_jobs_followup_cycle_id_followup_attempt_key UNIQUE (followup_cycle_id, followup_attempt);


--
-- Name: message_jobs message_jobs_idempotency_key_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_jobs
    ADD CONSTRAINT message_jobs_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: message_jobs message_jobs_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_jobs
    ADD CONSTRAINT message_jobs_pkey PRIMARY KEY (id);


--
-- Name: moderator_tasks moderator_tasks_exchange_id_kind_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.moderator_tasks
    ADD CONSTRAINT moderator_tasks_exchange_id_kind_key UNIQUE (exchange_id, kind);


--
-- Name: moderator_tasks moderator_tasks_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.moderator_tasks
    ADD CONSTRAINT moderator_tasks_pkey PRIMARY KEY (id);


--
-- Name: notification_templates notification_templates_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.notification_templates
    ADD CONSTRAINT notification_templates_pkey PRIMARY KEY (code, version);


--
-- Name: organization_participation organization_participation_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.organization_participation
    ADD CONSTRAINT organization_participation_pkey PRIMARY KEY (id);


--
-- Name: photo_screenings photo_screenings_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.photo_screenings
    ADD CONSTRAINT photo_screenings_pkey PRIMARY KEY (id);


--
-- Name: pilot_controls pilot_controls_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.pilot_controls
    ADD CONSTRAINT pilot_controls_pkey PRIMARY KEY (singleton);


--
-- Name: policy_acknowledgments policy_acknowledgments_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.policy_acknowledgments
    ADD CONSTRAINT policy_acknowledgments_pkey PRIMARY KEY (id);


--
-- Name: policy_versions policy_versions_kind_version_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.policy_versions
    ADD CONSTRAINT policy_versions_kind_version_key UNIQUE (kind, version);


--
-- Name: policy_versions policy_versions_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.policy_versions
    ADD CONSTRAINT policy_versions_pkey PRIMARY KEY (id);


--
-- Name: privacy_deletion_requests privacy_deletion_requests_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.privacy_deletion_requests
    ADD CONSTRAINT privacy_deletion_requests_pkey PRIMARY KEY (id);


--
-- Name: private_messages private_messages_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.private_messages
    ADD CONSTRAINT private_messages_pkey PRIMARY KEY (id);


--
-- Name: recall_reviews recall_reviews_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.recall_reviews
    ADD CONSTRAINT recall_reviews_pkey PRIMARY KEY (id);


--
-- Name: registration_sessions registration_sessions_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.registration_sessions
    ADD CONSTRAINT registration_sessions_pkey PRIMARY KEY (id);


--
-- Name: reporting_archives reporting_archives_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.reporting_archives
    ADD CONSTRAINT reporting_archives_pkey PRIMARY KEY (id);


--
-- Name: representations representations_id_representative_id_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.representations
    ADD CONSTRAINT representations_id_representative_id_key UNIQUE (id, representative_id);


--
-- Name: representations representations_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.representations
    ADD CONSTRAINT representations_pkey PRIMARY KEY (id);


--
-- Name: request_intents request_intents_exchange_id_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.request_intents
    ADD CONSTRAINT request_intents_exchange_id_key UNIQUE (exchange_id);


--
-- Name: request_intents request_intents_idempotency_key_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.request_intents
    ADD CONSTRAINT request_intents_idempotency_key_key UNIQUE (idempotency_key);


--
-- Name: request_intents request_intents_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.request_intents
    ADD CONSTRAINT request_intents_pkey PRIMARY KEY (id);


--
-- Name: resources resources_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.resources
    ADD CONSTRAINT resources_pkey PRIMARY KEY (id);


--
-- Name: restrictions restrictions_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.restrictions
    ADD CONSTRAINT restrictions_pkey PRIMARY KEY (id);


--
-- Name: retention_holds retention_holds_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.retention_holds
    ADD CONSTRAINT retention_holds_pkey PRIMARY KEY (id);


--
-- Name: retention_rules retention_rules_data_class_policy_id_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.retention_rules
    ADD CONSTRAINT retention_rules_data_class_policy_id_key UNIQUE (data_class, policy_id);


--
-- Name: retention_rules retention_rules_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.retention_rules
    ADD CONSTRAINT retention_rules_pkey PRIMARY KEY (id);


--
-- Name: sensitive_access_events sensitive_access_events_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.sensitive_access_events
    ADD CONSTRAINT sensitive_access_events_pkey PRIMARY KEY (id);


--
-- Name: service_areas service_areas_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.service_areas
    ADD CONSTRAINT service_areas_pkey PRIMARY KEY (id);


--
-- Name: service_areas service_areas_policy_id_zip_code_key; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.service_areas
    ADD CONSTRAINT service_areas_policy_id_zip_code_key UNIQUE (policy_id, zip_code);


--
-- Name: simulated_sms_messages simulated_sms_messages_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.simulated_sms_messages
    ADD CONSTRAINT simulated_sms_messages_pkey PRIMARY KEY (id);


--
-- Name: sms_deliveries sms_deliveries_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.sms_deliveries
    ADD CONSTRAINT sms_deliveries_pkey PRIMARY KEY (id);


--
-- Name: staff_credentials staff_credentials_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.staff_credentials
    ADD CONSTRAINT staff_credentials_pkey PRIMARY KEY (account_id);


--
-- Name: team_profiles team_profiles_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.team_profiles
    ADD CONSTRAINT team_profiles_pkey PRIMARY KEY (id);


--
-- Name: transport_barriers transport_barriers_pkey; Type: CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.transport_barriers
    ADD CONSTRAINT transport_barriers_pkey PRIMARY KEY (id);


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
-- Name: active_account_holds; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX active_account_holds ON freedme.restrictions USING btree (account_id) WHERE (released_at IS NULL);


--
-- Name: active_listing_holds; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX active_listing_holds ON freedme.restrictions USING btree (listing_id) WHERE (released_at IS NULL);


--
-- Name: activity_window; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX activity_window ON freedme.activity_events USING btree (account_id, action, occurred_at);


--
-- Name: archive_withdrawn_listing; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX archive_withdrawn_listing ON freedme.reporting_archives USING btree (listing_id) WHERE (exchange_id IS NULL);


--
-- Name: contact_consent_history; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX contact_consent_history ON freedme.consent_events USING btree (contact_id, purpose, occurred_at DESC, id DESC);


--
-- Name: donor_inventory; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX donor_inventory ON freedme.listings USING btree (donor_id, created_at DESC);


--
-- Name: donor_pending_questions; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX donor_pending_questions ON freedme.equipment_questions USING btree (donor_id, asked_at) WHERE (state = 'pending'::text);


--
-- Name: exchange_deadlines; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX exchange_deadlines ON freedme.exchanges USING btree (pending_expires_at) WHERE (state = 'pending'::text);


--
-- Name: exchange_requester_history; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX exchange_requester_history ON freedme.exchanges USING btree (requester_id, requested_at DESC);


--
-- Name: index_accounts_on_last_activity_at; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX index_accounts_on_last_activity_at ON freedme.accounts USING btree (last_activity_at);


--
-- Name: index_exchanges_on_retention_ended_at; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX index_exchanges_on_retention_ended_at ON freedme.exchanges USING btree (retention_ended_at);


--
-- Name: index_identity_document_uploads_on_account_id_and_created_at; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX index_identity_document_uploads_on_account_id_and_created_at ON freedme.identity_document_uploads USING btree (account_id, created_at);


--
-- Name: index_identity_document_uploads_on_purge_due_at; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX index_identity_document_uploads_on_purge_due_at ON freedme.identity_document_uploads USING btree (purge_due_at);


--
-- Name: index_listing_review_alerts_on_account_id_and_revision_id; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX index_listing_review_alerts_on_account_id_and_revision_id ON freedme.listing_review_alerts USING btree (account_id, revision_id);


--
-- Name: index_privacy_deletion_requests_on_account_id; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX index_privacy_deletion_requests_on_account_id ON freedme.privacy_deletion_requests USING btree (account_id);


--
-- Name: index_reporting_archives_on_exchange_id; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX index_reporting_archives_on_exchange_id ON freedme.reporting_archives USING btree (exchange_id);


--
-- Name: index_simulated_sms_messages_on_idempotency_key; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX index_simulated_sms_messages_on_idempotency_key ON freedme.simulated_sms_messages USING btree (idempotency_key);


--
-- Name: index_sms_deliveries_on_idempotency_key; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX index_sms_deliveries_on_idempotency_key ON freedme.sms_deliveries USING btree (idempotency_key);


--
-- Name: index_sms_deliveries_on_state_and_created_at; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX index_sms_deliveries_on_state_and_created_at ON freedme.sms_deliveries USING btree (state, created_at);


--
-- Name: index_staff_credentials_on_username; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX index_staff_credentials_on_username ON freedme.staff_credentials USING btree (username);


--
-- Name: listing_search; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX listing_search ON freedme.listing_revisions USING gin (to_tsvector('english'::regconfig, ((title || ' '::text) || description)));


--
-- Name: moderator_work_queue; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX moderator_work_queue ON freedme.moderator_tasks USING btree (due_at) WHERE (state = ANY (ARRAY['open'::text, 'in_progress'::text]));


--
-- Name: offer_deadlines; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX offer_deadlines ON freedme.exchanges USING btree (offer_expires_at) WHERE (state = 'offered'::text);


--
-- Name: one_active_allocation_per_item; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX one_active_allocation_per_item ON freedme.exchanges USING btree (listing_id) WHERE (state = ANY (ARRAY['pending'::text, 'offered'::text, 'reserved'::text, 'loaned'::text]));


--
-- Name: one_live_mobile_per_account; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX one_live_mobile_per_account ON freedme.account_contacts USING btree (account_id) WHERE ((kind = 'mobile'::text) AND (revoked_at IS NULL));


--
-- Name: one_live_phone_owner; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX one_live_phone_owner ON freedme.account_contacts USING btree (lookup_hmac) WHERE ((kind = 'mobile'::text) AND (revoked_at IS NULL) AND (NOT staff_notification));


--
-- Name: pending_identity_intents; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX pending_identity_intents ON freedme.request_intents USING btree (requester_id, created_at DESC);


--
-- Name: photo_screenings_content_policy; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX photo_screenings_content_policy ON freedme.photo_screenings USING btree (account_id, image_digest, policy_key);


--
-- Name: queued_messages; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX queued_messages ON freedme.message_jobs USING btree (due_at) WHERE (state = 'queued'::text);


--
-- Name: requester_question_history; Type: INDEX; Schema: freedme; Owner: -
--

CREATE INDEX requester_question_history ON freedme.equipment_questions USING btree (requester_id, listing_id, asked_at);


--
-- Name: single_handoff_confirmation; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX single_handoff_confirmation ON freedme.exchange_events USING btree (exchange_id) WHERE (event_type = 'handoff_confirmed'::text);


--
-- Name: single_return_confirmation; Type: INDEX; Schema: freedme; Owner: -
--

CREATE UNIQUE INDEX single_return_confirmation ON freedme.exchange_events USING btree (exchange_id) WHERE (event_type = 'return_confirmed'::text);


--
-- Name: agreements agreement_immutable; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER agreement_immutable BEFORE DELETE OR UPDATE ON freedme.agreements FOR EACH ROW EXECUTE FUNCTION freedme.prevent_history_mutation();


--
-- Name: audit_events audit_append_only; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER audit_append_only BEFORE DELETE OR UPDATE ON freedme.audit_events FOR EACH ROW EXECUTE FUNCTION freedme.prevent_history_mutation();


--
-- Name: consent_events consent_append_only; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER consent_append_only BEFORE DELETE OR UPDATE ON freedme.consent_events FOR EACH ROW EXECUTE FUNCTION freedme.prevent_history_mutation();


--
-- Name: identity_evidence evidence_gate; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER evidence_gate BEFORE INSERT ON freedme.identity_evidence FOR EACH ROW EXECUTE FUNCTION freedme.evidence_collection_gate();


--
-- Name: exchanges exchange_guard; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER exchange_guard BEFORE INSERT OR UPDATE ON freedme.exchanges FOR EACH ROW EXECUTE FUNCTION freedme.guard_exchange();


--
-- Name: listing_revisions freeze_submitted_revision; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER freeze_submitted_revision BEFORE DELETE OR UPDATE ON freedme.listing_revisions FOR EACH ROW EXECUTE FUNCTION freedme.frozen_revision();


--
-- Name: handoff_acceptances handoff_acceptance_guard; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER handoff_acceptance_guard BEFORE INSERT ON freedme.handoff_acceptances FOR EACH ROW EXECUTE FUNCTION freedme.guard_handoff_acceptance();


--
-- Name: handoff_acceptances handoff_acceptance_immutable; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER handoff_acceptance_immutable BEFORE DELETE OR UPDATE ON freedme.handoff_acceptances FOR EACH ROW EXECUTE FUNCTION freedme.prevent_history_mutation();


--
-- Name: handoff_proposals handoff_proposal_guard; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER handoff_proposal_guard BEFORE INSERT ON freedme.handoff_proposals FOR EACH ROW EXECUTE FUNCTION freedme.guard_handoff_proposal();


--
-- Name: handoff_proposals handoff_proposal_immutable; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER handoff_proposal_immutable BEFORE DELETE OR UPDATE ON freedme.handoff_proposals FOR EACH ROW EXECUTE FUNCTION freedme.prevent_history_mutation();


--
-- Name: exchange_events lifecycle_append_only; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER lifecycle_append_only BEFORE DELETE OR UPDATE ON freedme.exchange_events FOR EACH ROW EXECUTE FUNCTION freedme.prevent_history_mutation();


--
-- Name: listings publication_guard; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER publication_guard BEFORE INSERT OR UPDATE ON freedme.listings FOR EACH ROW EXECUTE FUNCTION freedme.guard_publication();


--
-- Name: exchanges request_identity_required; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE CONSTRAINT TRIGGER request_identity_required AFTER INSERT OR UPDATE ON freedme.exchanges DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION freedme.validate_verified_request();


--
-- Name: exchange_events transfer_event_guard; Type: TRIGGER; Schema: freedme; Owner: -
--

CREATE TRIGGER transfer_event_guard BEFORE INSERT ON freedme.exchange_events FOR EACH ROW EXECUTE FUNCTION freedme.guard_transfer_event();


--
-- Name: account_contacts account_contacts_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.account_contacts
    ADD CONSTRAINT account_contacts_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: account_notices account_notices_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.account_notices
    ADD CONSTRAINT account_notices_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: account_notices account_notices_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.account_notices
    ADD CONSTRAINT account_notices_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: account_notices account_notices_listing_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.account_notices
    ADD CONSTRAINT account_notices_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES freedme.listings(id);


--
-- Name: account_roles account_roles_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.account_roles
    ADD CONSTRAINT account_roles_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: account_roles account_roles_granted_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.account_roles
    ADD CONSTRAINT account_roles_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES freedme.accounts(id);


--
-- Name: action_tokens action_tokens_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.action_tokens
    ADD CONSTRAINT action_tokens_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: action_tokens action_tokens_case_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.action_tokens
    ADD CONSTRAINT action_tokens_case_id_fkey FOREIGN KEY (case_id) REFERENCES freedme.cases(id);


--
-- Name: action_tokens action_tokens_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.action_tokens
    ADD CONSTRAINT action_tokens_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: activity_events activity_events_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.activity_events
    ADD CONSTRAINT activity_events_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: activity_events activity_events_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.activity_events
    ADD CONSTRAINT activity_events_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: agreements agreements_accepted_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.agreements
    ADD CONSTRAINT agreements_accepted_by_fkey FOREIGN KEY (accepted_by) REFERENCES freedme.accounts(id);


--
-- Name: agreements agreements_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.agreements
    ADD CONSTRAINT agreements_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: agreements agreements_terms_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.agreements
    ADD CONSTRAINT agreements_terms_policy_id_fkey FOREIGN KEY (terms_policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: audit_events audit_events_actor_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.audit_events
    ADD CONSTRAINT audit_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES freedme.accounts(id);


--
-- Name: auth_challenges auth_challenges_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.auth_challenges
    ADD CONSTRAINT auth_challenges_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: borrower_fields borrower_fields_evidence_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.borrower_fields
    ADD CONSTRAINT borrower_fields_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES freedme.identity_evidence(id);


--
-- Name: case_actions case_actions_actor_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.case_actions
    ADD CONSTRAINT case_actions_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES freedme.accounts(id);


--
-- Name: case_actions case_actions_case_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.case_actions
    ADD CONSTRAINT case_actions_case_id_fkey FOREIGN KEY (case_id) REFERENCES freedme.cases(id);


--
-- Name: cases cases_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.cases
    ADD CONSTRAINT cases_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: cases cases_listing_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.cases
    ADD CONSTRAINT cases_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES freedme.listings(id);


--
-- Name: cases cases_owner_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.cases
    ADD CONSTRAINT cases_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES freedme.accounts(id);


--
-- Name: cases cases_reporter_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.cases
    ADD CONSTRAINT cases_reporter_id_fkey FOREIGN KEY (reporter_id) REFERENCES freedme.accounts(id);


--
-- Name: consent_events consent_events_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.consent_events
    ADD CONSTRAINT consent_events_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: consent_events consent_events_contact_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.consent_events
    ADD CONSTRAINT consent_events_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES freedme.account_contacts(id);


--
-- Name: consent_events consent_events_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.consent_events
    ADD CONSTRAINT consent_events_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: deletion_jobs deletion_jobs_rule_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.deletion_jobs
    ADD CONSTRAINT deletion_jobs_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES freedme.retention_rules(id);


--
-- Name: disclosure_grants disclosure_grants_consent_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.disclosure_grants
    ADD CONSTRAINT disclosure_grants_consent_policy_id_fkey FOREIGN KEY (consent_policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: disclosure_grants disclosure_grants_consented_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.disclosure_grants
    ADD CONSTRAINT disclosure_grants_consented_by_fkey FOREIGN KEY (consented_by) REFERENCES freedme.accounts(id);


--
-- Name: disclosure_grants disclosure_grants_donor_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.disclosure_grants
    ADD CONSTRAINT disclosure_grants_donor_id_fkey FOREIGN KEY (donor_id) REFERENCES freedme.accounts(id);


--
-- Name: disclosure_grants disclosure_grants_evidence_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.disclosure_grants
    ADD CONSTRAINT disclosure_grants_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES freedme.identity_evidence(id);


--
-- Name: disclosure_grants disclosure_grants_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.disclosure_grants
    ADD CONSTRAINT disclosure_grants_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: equipment_configurations equipment_configurations_category_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.equipment_configurations
    ADD CONSTRAINT equipment_configurations_category_id_fkey FOREIGN KEY (category_id) REFERENCES freedme.categories(id);


--
-- Name: equipment_configurations equipment_configurations_guidance_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.equipment_configurations
    ADD CONSTRAINT equipment_configurations_guidance_policy_id_fkey FOREIGN KEY (guidance_policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: equipment_configurations equipment_configurations_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.equipment_configurations
    ADD CONSTRAINT equipment_configurations_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: equipment_questions equipment_questions_answered_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.equipment_questions
    ADD CONSTRAINT equipment_questions_answered_by_fkey FOREIGN KEY (answered_by) REFERENCES freedme.accounts(id);


--
-- Name: equipment_questions equipment_questions_listing_id_donor_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.equipment_questions
    ADD CONSTRAINT equipment_questions_listing_id_donor_id_fkey FOREIGN KEY (listing_id, donor_id) REFERENCES freedme.listings(id, donor_id);


--
-- Name: equipment_questions equipment_questions_requester_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.equipment_questions
    ADD CONSTRAINT equipment_questions_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES freedme.accounts(id);


--
-- Name: exchange_display_preferences exchange_display_preferences_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchange_display_preferences
    ADD CONSTRAINT exchange_display_preferences_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: exchange_display_preferences exchange_display_preferences_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchange_display_preferences
    ADD CONSTRAINT exchange_display_preferences_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: exchange_display_preferences exchange_display_preferences_replaced_by_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchange_display_preferences
    ADD CONSTRAINT exchange_display_preferences_replaced_by_exchange_id_fkey FOREIGN KEY (replaced_by_exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: exchange_events exchange_events_actor_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchange_events
    ADD CONSTRAINT exchange_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES freedme.accounts(id);


--
-- Name: exchange_events exchange_events_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchange_events
    ADD CONSTRAINT exchange_events_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: exchanges exchanges_listing_id_donor_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchanges
    ADD CONSTRAINT exchanges_listing_id_donor_id_fkey FOREIGN KEY (listing_id, donor_id) REFERENCES freedme.listings(id, donor_id);


--
-- Name: exchanges exchanges_listing_id_revision_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchanges
    ADD CONSTRAINT exchanges_listing_id_revision_id_fkey FOREIGN KEY (listing_id, revision_id) REFERENCES freedme.listing_revisions(listing_id, id);


--
-- Name: exchanges exchanges_representation_id_requester_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchanges
    ADD CONSTRAINT exchanges_representation_id_requester_id_fkey FOREIGN KEY (representation_id, requester_id) REFERENCES freedme.representations(id, representative_id);


--
-- Name: exchanges exchanges_requester_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.exchanges
    ADD CONSTRAINT exchanges_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES freedme.accounts(id);


--
-- Name: identity_document_uploads fk_rails_14513dcd4b; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_document_uploads
    ADD CONSTRAINT fk_rails_14513dcd4b FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: reporting_archives fk_rails_1563ba718c; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.reporting_archives
    ADD CONSTRAINT fk_rails_1563ba718c FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: privacy_deletion_requests fk_rails_2ba5d5c079; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.privacy_deletion_requests
    ADD CONSTRAINT fk_rails_2ba5d5c079 FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: photo_screenings fk_rails_68393ec1ec; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.photo_screenings
    ADD CONSTRAINT fk_rails_68393ec1ec FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: listing_review_alerts fk_rails_6b28f5799a; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_review_alerts
    ADD CONSTRAINT fk_rails_6b28f5799a FOREIGN KEY (account_id) REFERENCES freedme.accounts(id) ON DELETE CASCADE;


--
-- Name: listing_review_alerts fk_rails_6d444b30f1; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_review_alerts
    ADD CONSTRAINT fk_rails_6d444b30f1 FOREIGN KEY (revision_id) REFERENCES freedme.listing_revisions(id) ON DELETE CASCADE;


--
-- Name: identity_document_uploads fk_rails_8f764adc89; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_document_uploads
    ADD CONSTRAINT fk_rails_8f764adc89 FOREIGN KEY (revision_id) REFERENCES freedme.listing_revisions(id);


--
-- Name: identity_document_uploads fk_rails_9007e59e49; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_document_uploads
    ADD CONSTRAINT fk_rails_9007e59e49 FOREIGN KEY (listing_id) REFERENCES freedme.listings(id);


--
-- Name: reporting_archives fk_rails_d711ea3a35; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.reporting_archives
    ADD CONSTRAINT fk_rails_d711ea3a35 FOREIGN KEY (listing_id) REFERENCES freedme.listings(id);


--
-- Name: identity_document_uploads fk_rails_e001357a2e; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_document_uploads
    ADD CONSTRAINT fk_rails_e001357a2e FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: followup_cycles followup_cycles_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.followup_cycles
    ADD CONSTRAINT followup_cycles_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: gateway_events gateway_events_attempt_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.gateway_events
    ADD CONSTRAINT gateway_events_attempt_id_fkey FOREIGN KEY (attempt_id) REFERENCES freedme.message_attempts(id);


--
-- Name: handoff_acceptances handoff_acceptances_accepted_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.handoff_acceptances
    ADD CONSTRAINT handoff_acceptances_accepted_by_fkey FOREIGN KEY (accepted_by) REFERENCES freedme.accounts(id);


--
-- Name: handoff_acceptances handoff_acceptances_proposal_id_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.handoff_acceptances
    ADD CONSTRAINT handoff_acceptances_proposal_id_exchange_id_fkey FOREIGN KEY (proposal_id, exchange_id) REFERENCES freedme.handoff_proposals(id, exchange_id);


--
-- Name: handoff_proposals handoff_proposals_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.handoff_proposals
    ADD CONSTRAINT handoff_proposals_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: handoff_proposals handoff_proposals_proposed_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.handoff_proposals
    ADD CONSTRAINT handoff_proposals_proposed_by_fkey FOREIGN KEY (proposed_by) REFERENCES freedme.accounts(id);


--
-- Name: identity_evidence identity_evidence_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_evidence
    ADD CONSTRAINT identity_evidence_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: identity_evidence identity_evidence_replaces_evidence_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_evidence
    ADD CONSTRAINT identity_evidence_replaces_evidence_id_fkey FOREIGN KEY (replaces_evidence_id) REFERENCES freedme.identity_evidence(id);


--
-- Name: identity_evidence identity_evidence_representation_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_evidence
    ADD CONSTRAINT identity_evidence_representation_id_fkey FOREIGN KEY (representation_id) REFERENCES freedme.representations(id);


--
-- Name: identity_evidence identity_evidence_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_evidence
    ADD CONSTRAINT identity_evidence_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES freedme.accounts(id);


--
-- Name: identity_evidence identity_evidence_submitted_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.identity_evidence
    ADD CONSTRAINT identity_evidence_submitted_by_fkey FOREIGN KEY (submitted_by) REFERENCES freedme.accounts(id);


--
-- Name: listing_photos listing_photos_revision_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_photos
    ADD CONSTRAINT listing_photos_revision_id_fkey FOREIGN KEY (revision_id) REFERENCES freedme.listing_revisions(id);


--
-- Name: listing_reviews listing_reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_reviews
    ADD CONSTRAINT listing_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES freedme.accounts(id);


--
-- Name: listing_reviews listing_reviews_revision_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_reviews
    ADD CONSTRAINT listing_reviews_revision_id_fkey FOREIGN KEY (revision_id) REFERENCES freedme.listing_revisions(id);


--
-- Name: listing_revisions listing_revisions_configuration_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_revisions
    ADD CONSTRAINT listing_revisions_configuration_id_fkey FOREIGN KEY (configuration_id) REFERENCES freedme.equipment_configurations(id);


--
-- Name: listing_revisions listing_revisions_listing_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_revisions
    ADD CONSTRAINT listing_revisions_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES freedme.listings(id);


--
-- Name: listing_revisions listing_revisions_service_area_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listing_revisions
    ADD CONSTRAINT listing_revisions_service_area_id_fkey FOREIGN KEY (service_area_id) REFERENCES freedme.service_areas(id);


--
-- Name: listings listings_donor_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listings
    ADD CONSTRAINT listings_donor_id_fkey FOREIGN KEY (donor_id) REFERENCES freedme.accounts(id);


--
-- Name: listings listings_id_approved_revision_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listings
    ADD CONSTRAINT listings_id_approved_revision_id_fkey FOREIGN KEY (id, approved_revision_id) REFERENCES freedme.listing_revisions(listing_id, id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: listings listings_id_current_revision_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.listings
    ADD CONSTRAINT listings_id_current_revision_id_fkey FOREIGN KEY (id, current_revision_id) REFERENCES freedme.listing_revisions(listing_id, id) DEFERRABLE INITIALLY DEFERRED;


--
-- Name: loan_terms_history loan_terms_history_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.loan_terms_history
    ADD CONSTRAINT loan_terms_history_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: loan_terms_history loan_terms_history_reported_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.loan_terms_history
    ADD CONSTRAINT loan_terms_history_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES freedme.accounts(id);


--
-- Name: loan_terms_history loan_terms_history_timing_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.loan_terms_history
    ADD CONSTRAINT loan_terms_history_timing_policy_id_fkey FOREIGN KEY (timing_policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: message_attempts message_attempts_job_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_attempts
    ADD CONSTRAINT message_attempts_job_id_fkey FOREIGN KEY (job_id) REFERENCES freedme.message_jobs(id);


--
-- Name: message_jobs message_jobs_contact_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_jobs
    ADD CONSTRAINT message_jobs_contact_id_fkey FOREIGN KEY (contact_id) REFERENCES freedme.account_contacts(id);


--
-- Name: message_jobs message_jobs_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_jobs
    ADD CONSTRAINT message_jobs_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: message_jobs message_jobs_followup_cycle_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_jobs
    ADD CONSTRAINT message_jobs_followup_cycle_id_fkey FOREIGN KEY (followup_cycle_id) REFERENCES freedme.followup_cycles(id);


--
-- Name: message_jobs message_jobs_listing_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_jobs
    ADD CONSTRAINT message_jobs_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES freedme.listings(id);


--
-- Name: message_jobs message_jobs_question_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_jobs
    ADD CONSTRAINT message_jobs_question_id_fkey FOREIGN KEY (question_id) REFERENCES freedme.equipment_questions(id);


--
-- Name: message_jobs message_jobs_recipient_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_jobs
    ADD CONSTRAINT message_jobs_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES freedme.accounts(id);


--
-- Name: message_jobs message_jobs_template_code_template_version_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.message_jobs
    ADD CONSTRAINT message_jobs_template_code_template_version_fkey FOREIGN KEY (template_code, template_version) REFERENCES freedme.notification_templates(code, version);


--
-- Name: moderator_tasks moderator_tasks_assigned_to_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.moderator_tasks
    ADD CONSTRAINT moderator_tasks_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES freedme.accounts(id);


--
-- Name: moderator_tasks moderator_tasks_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.moderator_tasks
    ADD CONSTRAINT moderator_tasks_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: pilot_controls pilot_controls_loan_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.pilot_controls
    ADD CONSTRAINT pilot_controls_loan_policy_id_fkey FOREIGN KEY (loan_policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: pilot_controls pilot_controls_privacy_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.pilot_controls
    ADD CONSTRAINT pilot_controls_privacy_policy_id_fkey FOREIGN KEY (privacy_policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: policy_acknowledgments policy_acknowledgments_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.policy_acknowledgments
    ADD CONSTRAINT policy_acknowledgments_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: policy_acknowledgments policy_acknowledgments_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.policy_acknowledgments
    ADD CONSTRAINT policy_acknowledgments_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: policy_acknowledgments policy_acknowledgments_listing_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.policy_acknowledgments
    ADD CONSTRAINT policy_acknowledgments_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES freedme.listings(id);


--
-- Name: policy_acknowledgments policy_acknowledgments_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.policy_acknowledgments
    ADD CONSTRAINT policy_acknowledgments_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: policy_versions policy_versions_approved_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.policy_versions
    ADD CONSTRAINT policy_versions_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES freedme.accounts(id);


--
-- Name: private_messages private_messages_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.private_messages
    ADD CONSTRAINT private_messages_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: private_messages private_messages_messaging_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.private_messages
    ADD CONSTRAINT private_messages_messaging_policy_id_fkey FOREIGN KEY (messaging_policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: private_messages private_messages_recipient_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.private_messages
    ADD CONSTRAINT private_messages_recipient_id_fkey FOREIGN KEY (recipient_id) REFERENCES freedme.accounts(id);


--
-- Name: private_messages private_messages_sender_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.private_messages
    ADD CONSTRAINT private_messages_sender_id_fkey FOREIGN KEY (sender_id) REFERENCES freedme.accounts(id);


--
-- Name: recall_reviews recall_reviews_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.recall_reviews
    ADD CONSTRAINT recall_reviews_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: recall_reviews recall_reviews_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.recall_reviews
    ADD CONSTRAINT recall_reviews_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES freedme.accounts(id);


--
-- Name: recall_reviews recall_reviews_revision_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.recall_reviews
    ADD CONSTRAINT recall_reviews_revision_id_fkey FOREIGN KEY (revision_id) REFERENCES freedme.listing_revisions(id);


--
-- Name: registration_sessions registration_sessions_challenge_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.registration_sessions
    ADD CONSTRAINT registration_sessions_challenge_id_fkey FOREIGN KEY (challenge_id) REFERENCES freedme.auth_challenges(id);


--
-- Name: registration_sessions registration_sessions_created_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.registration_sessions
    ADD CONSTRAINT registration_sessions_created_account_id_fkey FOREIGN KEY (created_account_id) REFERENCES freedme.accounts(id);


--
-- Name: registration_sessions registration_sessions_listing_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.registration_sessions
    ADD CONSTRAINT registration_sessions_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES freedme.listings(id);


--
-- Name: representations representations_authority_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.representations
    ADD CONSTRAINT representations_authority_policy_id_fkey FOREIGN KEY (authority_policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: representations representations_recipient_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.representations
    ADD CONSTRAINT representations_recipient_account_id_fkey FOREIGN KEY (recipient_account_id) REFERENCES freedme.accounts(id);


--
-- Name: representations representations_representative_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.representations
    ADD CONSTRAINT representations_representative_id_fkey FOREIGN KEY (representative_id) REFERENCES freedme.accounts(id);


--
-- Name: request_intents request_intents_evidence_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.request_intents
    ADD CONSTRAINT request_intents_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES freedme.identity_evidence(id);


--
-- Name: request_intents request_intents_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.request_intents
    ADD CONSTRAINT request_intents_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: request_intents request_intents_listing_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.request_intents
    ADD CONSTRAINT request_intents_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES freedme.listings(id);


--
-- Name: request_intents request_intents_representation_id_requester_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.request_intents
    ADD CONSTRAINT request_intents_representation_id_requester_id_fkey FOREIGN KEY (representation_id, requester_id) REFERENCES freedme.representations(id, representative_id);


--
-- Name: request_intents request_intents_requester_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.request_intents
    ADD CONSTRAINT request_intents_requester_id_fkey FOREIGN KEY (requester_id) REFERENCES freedme.accounts(id);


--
-- Name: resources resources_reviewer_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.resources
    ADD CONSTRAINT resources_reviewer_id_fkey FOREIGN KEY (reviewer_id) REFERENCES freedme.accounts(id);


--
-- Name: restrictions restrictions_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.restrictions
    ADD CONSTRAINT restrictions_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: restrictions restrictions_applied_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.restrictions
    ADD CONSTRAINT restrictions_applied_by_fkey FOREIGN KEY (applied_by) REFERENCES freedme.accounts(id);


--
-- Name: restrictions restrictions_case_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.restrictions
    ADD CONSTRAINT restrictions_case_id_fkey FOREIGN KEY (case_id) REFERENCES freedme.cases(id);


--
-- Name: restrictions restrictions_listing_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.restrictions
    ADD CONSTRAINT restrictions_listing_id_fkey FOREIGN KEY (listing_id) REFERENCES freedme.listings(id);


--
-- Name: restrictions restrictions_released_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.restrictions
    ADD CONSTRAINT restrictions_released_by_fkey FOREIGN KEY (released_by) REFERENCES freedme.accounts(id);


--
-- Name: retention_holds retention_holds_case_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.retention_holds
    ADD CONSTRAINT retention_holds_case_id_fkey FOREIGN KEY (case_id) REFERENCES freedme.cases(id);


--
-- Name: retention_holds retention_holds_created_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.retention_holds
    ADD CONSTRAINT retention_holds_created_by_fkey FOREIGN KEY (created_by) REFERENCES freedme.accounts(id);


--
-- Name: retention_rules retention_rules_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.retention_rules
    ADD CONSTRAINT retention_rules_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: sensitive_access_events sensitive_access_events_actor_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.sensitive_access_events
    ADD CONSTRAINT sensitive_access_events_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES freedme.accounts(id);


--
-- Name: sensitive_access_events sensitive_access_events_evidence_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.sensitive_access_events
    ADD CONSTRAINT sensitive_access_events_evidence_id_fkey FOREIGN KEY (evidence_id) REFERENCES freedme.identity_evidence(id);


--
-- Name: sensitive_access_events sensitive_access_events_grant_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.sensitive_access_events
    ADD CONSTRAINT sensitive_access_events_grant_id_fkey FOREIGN KEY (grant_id) REFERENCES freedme.disclosure_grants(id);


--
-- Name: service_areas service_areas_policy_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.service_areas
    ADD CONSTRAINT service_areas_policy_id_fkey FOREIGN KEY (policy_id) REFERENCES freedme.policy_versions(id);


--
-- Name: staff_credentials staff_credentials_account_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.staff_credentials
    ADD CONSTRAINT staff_credentials_account_id_fkey FOREIGN KEY (account_id) REFERENCES freedme.accounts(id);


--
-- Name: staff_credentials staff_credentials_email_contact_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.staff_credentials
    ADD CONSTRAINT staff_credentials_email_contact_id_fkey FOREIGN KEY (email_contact_id) REFERENCES freedme.account_contacts(id);


--
-- Name: transport_barriers transport_barriers_exchange_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.transport_barriers
    ADD CONSTRAINT transport_barriers_exchange_id_fkey FOREIGN KEY (exchange_id) REFERENCES freedme.exchanges(id);


--
-- Name: transport_barriers transport_barriers_reported_by_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.transport_barriers
    ADD CONSTRAINT transport_barriers_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES freedme.accounts(id);


--
-- Name: transport_barriers transport_barriers_resource_id_fkey; Type: FK CONSTRAINT; Schema: freedme; Owner: -
--

ALTER TABLE ONLY freedme.transport_barriers
    ADD CONSTRAINT transport_barriers_resource_id_fkey FOREIGN KEY (resource_id) REFERENCES freedme.resources(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO freedme,public;

REVOKE ALL ON ALL TABLES IN SCHEMA freedme FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA freedme FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA freedme REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA freedme REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
INSERT INTO "schema_migrations" (version) VALUES
('20261118000000'),
('20261117000000'),
('20261115000000'),
('20261114000000'),
('20261106000000'),
('20261030000000'),
('20261029000100'),
('20261029000000'),
('20261028000000'),
('20261027000000'),
('20261026000000');

