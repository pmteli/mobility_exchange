# frozen_string_literal: true
# Fresh install of FreeDME v0.2. Do not edit after applying; add future migrations.
# Migration API 7.1 is usable by Rails 7.1+ including Rails 8.x.
# Rails owns the transaction. Do not add disable_ddl_transaction!.
class CreateFreedmeV02Schema < ActiveRecord::Migration[7.1]
  SOURCE_SCHEMA_SHA256 = "ffdc0feed93ed896a73d4275208854158b533834e864387dc92f656af27bc9dc".freeze
  SCHEMA_SQL = <<~'FREEDME_SCHEMA_SQL'.freeze
    -- FreeDME PostgreSQL 18 schema v0.2 — PRS v0.10 + explicit decisions through 2026-10-26
    -- Design baseline, not a complete workflow/authorization implementation.
    -- Fresh database only. Apply with psql -v ON_ERROR_STOP=1 -f schema.sql.
    DO $$ BEGIN
     IF current_setting('server_version_num')::integer < 180000 THEN
      RAISE EXCEPTION 'PostgreSQL 18 or later is required';
     END IF;
    END $$;
    CREATE SCHEMA freedme;
    REVOKE ALL ON SCHEMA freedme FROM PUBLIC;
    SET LOCAL search_path = freedme, pg_catalog;
    
    -- FR003, FR026: One account can donate and request; contact is private.
    CREATE TABLE accounts (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    display_name text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 80),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','restricted','closed')),
    public_locality text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    closed_at timestamptz
    );
    
    -- FR003, FR021, FR026: Encrypted contact values; keyed HMAC lookup supports normalized phone uniqueness.
    CREATE TABLE account_contacts (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    account_id uuid NOT NULL REFERENCES accounts(id),
    kind text NOT NULL CHECK (kind IN ('mobile','email')),
    value_ciphertext bytea NOT NULL,
    lookup_hmac bytea NOT NULL,
    key_version text NOT NULL,
    verified_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
    );
    
    -- NFR003, section 9: Restricted staff authentication; MFA secrets are encrypted, passwords hashed.
    CREATE TABLE staff_credentials (
    account_id uuid PRIMARY KEY REFERENCES accounts(id),
    first_name_ciphertext bytea NOT NULL,
    last_name_ciphertext bytea NOT NULL,
    email_contact_id uuid NOT NULL REFERENCES account_contacts(id),
    password_digest text NOT NULL,
    mfa_secret_ciphertext bytea NOT NULL,
    mfa_enrolled_at timestamptz NOT NULL,
    key_version text NOT NULL
    );
    
    -- FR003: Staff authorization is explicit; donor and recipient roles are not mutually exclusive.
    CREATE TABLE account_roles (
    account_id uuid NOT NULL REFERENCES accounts(id),
    role text NOT NULL CHECK (role IN ('donor','recipient','caregiver','helper','moderator','support','administrator')),
    granted_at timestamptz NOT NULL DEFAULT now(),
    granted_by uuid REFERENCES accounts(id),
    PRIMARY KEY (account_id,role)
    );
    
    -- FR026: Store keyed OTP digests, never codes; rate limiting also spans replacement challenges.
    CREATE TABLE auth_challenges (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    account_id uuid REFERENCES accounts(id),
    phone_lookup_hmac bytea NOT NULL,
    code_digest bytea NOT NULL,
    expires_at timestamptz NOT NULL,
    failed_attempts smallint NOT NULL DEFAULT 0 CHECK (failed_attempts BETWEEN 0 AND 3),
    consumed_at timestamptz,
    invalidated_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (expires_at > created_at),
    CHECK (failed_attempts < 3 OR invalidated_at IS NOT NULL)
    );
    
    -- FR020–022, FR029, FR033, FR039, DEC01–06: Immutable approved policy/configuration snapshots; no unapproved defaults.
    CREATE TABLE policy_versions (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    kind text NOT NULL,
    version text NOT NULL,
    content_sha256 text NOT NULL,
    content_object_key text NOT NULL,
    configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
    approved_by uuid REFERENCES accounts(id),
    approved_at timestamptz,
    effective_at timestamptz,
    UNIQUE (kind,version),
    CHECK ((approved_at IS NULL) = (approved_by IS NULL))
    );
    
    -- DEC01, DEC03: Explicit enablement gate; initially no collection or loans.
    CREATE TABLE pilot_controls (
    singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
    loans_enabled boolean NOT NULL DEFAULT false,
    evidence_collection_enabled boolean NOT NULL DEFAULT false,
    privacy_policy_id uuid REFERENCES policy_versions(id),
    loan_policy_id uuid REFERENCES policy_versions(id),
    CHECK (NOT evidence_collection_enabled OR privacy_policy_id IS NOT NULL),
    CHECK (NOT loans_enabled OR (evidence_collection_enabled AND loan_policy_id IS NOT NULL))
    );
    
    -- FR004, FR033: Only the six scoped equipment categories are seeded; configuration approval remains separate.
    CREATE TABLE categories (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    code text NOT NULL UNIQUE,
    name text NOT NULL UNIQUE
    );
    
    -- FR033, DEC02: Versioned category/configuration allowlist; no approved configurations seeded.
    CREATE TABLE equipment_configurations (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    category_id uuid NOT NULL REFERENCES categories(id),
    policy_id uuid NOT NULL REFERENCES policy_versions(id),
    code text NOT NULL,
    allowed boolean NOT NULL DEFAULT false,
    guidance_policy_id uuid REFERENCES policy_versions(id),
    UNIQUE (policy_id,category_id,code)
    );
    
    -- FR007, FR033, OQ002: Private eligible ZIP list; centroid only, never a household coordinate.
    CREATE TABLE service_areas (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    policy_id uuid NOT NULL REFERENCES policy_versions(id),
    zip_code text NOT NULL CHECK (zip_code ~ '^[0-9]{5}$'),
    county text NOT NULL,
    city text NOT NULL,
    centroid_lat numeric(9,6) CHECK (centroid_lat BETWEEN -90 AND 90),
    centroid_lon numeric(9,6) CHECK (centroid_lon BETWEEN -180 AND 180),
    donor_eligible boolean NOT NULL DEFAULT false,
    recipient_eligible boolean NOT NULL DEFAULT false,
    UNIQUE (policy_id,zip_code)
    );
    
    -- FR004, FR011–012, FR025: One transferable item; versioned content and allocation history are separate.
    CREATE TABLE listings (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    donor_id uuid NOT NULL REFERENCES accounts(id),
    status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','pending_review','available','reserved','donated','loaned','unavailable','rejected','withdrawn')),
    current_revision_id uuid,
    approved_revision_id uuid,
    last_possession_confirmed_at timestamptz,
    availability_valid_until timestamptz,
    allocation_generation integer NOT NULL DEFAULT 0 CHECK (allocation_generation >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (id,donor_id)
    );
    
    -- FR004–006, FR012, FR020, FR034–035: Revision frozen on submission; accepted reservations reference exact revision.
    CREATE TABLE listing_revisions (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    listing_id uuid NOT NULL REFERENCES listings(id),
    revision_no integer NOT NULL CHECK (revision_no > 0),
    configuration_id uuid NOT NULL REFERENCES equipment_configurations(id),
    service_area_id uuid NOT NULL REFERENCES service_areas(id),
    offer_kind text NOT NULL CHECK (offer_kind IN ('gift','loan')),
    loan_until date,
    title text NOT NULL,
    description text NOT NULL,
    public_locality text NOT NULL,
    condition_code text NOT NULL CHECK(condition_code IN ('new','gently_used','good','requires_repairs')),
    condition_description text NOT NULL,
    no_missing_parts_affirmed boolean NOT NULL DEFAULT false,
    fully_functional_affirmed boolean NOT NULL DEFAULT false,
    manufacturer text,
    model text,
    capacity_description text,
    missing_parts text, -- Legacy disclosures retained; not a new form field.
    known_defects text, -- Legacy disclosures retained; repair details live in description.
    modifications text NOT NULL,
    cleaning_status text NOT NULL,
    pickup_availability text NOT NULL,
    free_item_affirmed boolean NOT NULL DEFAULT false,
    truthfulness_affirmed boolean NOT NULL DEFAULT false,
    public_content_checked_at timestamptz,
    submitted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (listing_id,revision_no),
    UNIQUE (listing_id,id),
    CHECK ((offer_kind='gift' AND loan_until IS NULL) OR (offer_kind='loan' AND loan_until IS NOT NULL)),
    CHECK (loan_until IS NULL OR submitted_at IS NULL OR loan_until > (submitted_at AT TIME ZONE 'America/Los_Angeles')::date)
    );
    
    -- FR005, FR035: Restricted originals and sanitized derivatives; slot constraint caps at five.
    CREATE TABLE listing_photos (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    revision_id uuid NOT NULL REFERENCES listing_revisions(id),
    slot smallint NOT NULL CHECK (slot BETWEEN 1 AND 5),
    original_object_key text,
    sanitized_object_key text,
    mime_type text NOT NULL CHECK (mime_type IN ('image/jpeg','image/png')),
    byte_size integer NOT NULL CHECK (byte_size > 0 AND byte_size <= 5242880),
    metadata_stripped_at timestamptz,
    content_reviewed_at timestamptz,
    state text NOT NULL DEFAULT 'processing' CHECK (state IN ('processing','approved','rejected')),
    UNIQUE (revision_id,slot),
    CHECK (state <> 'approved' OR (sanitized_object_key IS NOT NULL AND metadata_stripped_at IS NOT NULL AND content_reviewed_at IS NOT NULL))
    );
    
    -- FR038: Manual regulator/manufacturer screening; no-match is not safety certification.
    CREATE TABLE recall_reviews (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    revision_id uuid NOT NULL REFERENCES listing_revisions(id),
    reviewer_id uuid NOT NULL REFERENCES accounts(id),
    source_url text NOT NULL,
    product_identification text NOT NULL,
    result text NOT NULL CHECK (result IN ('no_match','potential_match','confirmed_unresolved','insufficient_identification','resolved_under_policy')),
    notes_ciphertext bytea,
    policy_id uuid NOT NULL REFERENCES policy_versions(id),
    reviewed_at timestamptz NOT NULL DEFAULT now()
    );
    
    -- FR006: Accountable screening decisions tied to exact content.
    CREATE TABLE listing_reviews (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    revision_id uuid NOT NULL REFERENCES listing_revisions(id),
    reviewer_id uuid NOT NULL REFERENCES accounts(id),
    decision text NOT NULL CHECK (decision IN ('approved','changes_requested','rejected')),
    disclosures_checked boolean NOT NULL,
    recall_checked boolean NOT NULL,
    reason text NOT NULL,
    reviewed_at timestamptz NOT NULL DEFAULT now()
    );
    
    -- FR003, FR021, UJ003: Recipient need not have an account; authorization and minimum borrower data are private.
    CREATE TABLE representations (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    representative_id uuid NOT NULL REFERENCES accounts(id),
    recipient_account_id uuid REFERENCES accounts(id),
    relationship text NOT NULL CHECK (relationship IN ('caregiver','family','community_helper')),
    subject_reference_ciphertext bytea,
    authority_policy_id uuid NOT NULL REFERENCES policy_versions(id),
    authorized_at timestamptz NOT NULL,
    revoked_at timestamptz,
    UNIQUE (id,representative_id)
    );
    
    -- FR020, FR023–025: Single aggregate for request → offer → reservation; historical attempts never overwritten.
    CREATE TABLE exchanges (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    listing_id uuid NOT NULL,
    donor_id uuid NOT NULL,
    requester_id uuid NOT NULL REFERENCES accounts(id),
    representation_id uuid,
    revision_id uuid NOT NULL,
    state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','offered','reserved','loaned','completed','declined','expired','cancelled','closed_unavailable')),
    paused_reason text CHECK (paused_reason IN ('delivery_failure','opt_out','nonresponse','security','safety')),
    requested_loan_days integer CHECK (requested_loan_days > 0),
    proposed_start_date date,
    proposed_end_date date,
    requested_at timestamptz NOT NULL DEFAULT now(),
    pending_reminder_at timestamptz NOT NULL DEFAULT (now()+interval '24 hours'),
    pending_expires_at timestamptz NOT NULL DEFAULT (now()+interval '48 hours'),
    offered_at timestamptz,
    offer_expires_at timestamptz,
    reserved_at timestamptz,
    closed_at timestamptz,
    closure_reason text,
    idempotency_key uuid NOT NULL UNIQUE,
    FOREIGN KEY (listing_id,donor_id) REFERENCES listings(id,donor_id),
    FOREIGN KEY (listing_id,revision_id) REFERENCES listing_revisions(listing_id,id),
    FOREIGN KEY (representation_id,requester_id) REFERENCES representations(id,representative_id),
    UNIQUE (id,listing_id),
    CHECK (donor_id <> requester_id),
    CHECK (pending_reminder_at = requested_at + interval '24 hours'),
    CHECK (pending_expires_at = requested_at + interval '48 hours'),
    CHECK ((offered_at IS NULL) = (offer_expires_at IS NULL)),
    CHECK (offer_expires_at = offered_at + interval '24 hours'),
    CHECK (state NOT IN ('offered','reserved','loaned','completed') OR offered_at IS NOT NULL),
    CHECK (offered_at IS NULL OR offered_at >= requested_at),
    CHECK (state NOT IN ('reserved','loaned','completed') OR reserved_at IS NOT NULL),
    CHECK (reserved_at IS NULL OR (reserved_at >= offered_at AND reserved_at < offer_expires_at)),
    CHECK ((state IN ('completed','declined','expired','cancelled','closed_unavailable')) = (closed_at IS NOT NULL)),
    CHECK (proposed_end_date IS NULL OR (proposed_start_date IS NOT NULL AND proposed_end_date >= proposed_start_date))
    );
    
    -- FR020, FR034: Immutable accepted terms excluding evidence; encrypted snapshot has separate retention.
    CREATE TABLE agreements (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    exchange_id uuid NOT NULL UNIQUE REFERENCES exchanges(id),
    terms_policy_id uuid NOT NULL REFERENCES policy_versions(id),
    accepted_by uuid NOT NULL REFERENCES accounts(id),
    accepted_at timestamptz NOT NULL,
    terms_snapshot_ciphertext bytea NOT NULL,
    key_version text NOT NULL,
    snapshot_sha256 text NOT NULL
    );
    
    -- FR011, FR017, FR025, DEC06: Append-only lifecycle facts distinguish reservation, handoff, return and possession.
    CREATE TABLE exchange_events (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    exchange_id uuid NOT NULL REFERENCES exchanges(id),
    actor_id uuid REFERENCES accounts(id),
    event_type text NOT NULL CHECK (event_type IN ('requested','offered','reserved','cancelled','declined','expired','handoff_confirmed','return_reported','return_confirmed','possession_confirmed','reopened','unavailable','extension_reported','paused','resumed')),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    reason_code text,
    idempotency_key uuid NOT NULL UNIQUE
    );
    
    -- FR020, FR024, DEC06: Record optional date changes without silently rewriting accepted terms.
    CREATE TABLE loan_terms_history (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    exchange_id uuid NOT NULL REFERENCES exchanges(id),
    reported_by uuid NOT NULL REFERENCES accounts(id),
    starts_at timestamptz,
    due_at timestamptz,
    reason text NOT NULL CHECK (reason IN ('initial','extension','early_return')),
    timing_policy_id uuid NOT NULL REFERENCES policy_versions(id),
    reported_at timestamptz NOT NULL DEFAULT now(),
    CHECK (due_at IS NULL OR (starts_at IS NOT NULL AND due_at > starts_at))
    );
    
    -- FR004, FR022, FR029, FR039: Actor and exact policy recorded at submission/request/reservation.
    CREATE TABLE policy_acknowledgments (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    account_id uuid NOT NULL REFERENCES accounts(id),
    policy_id uuid NOT NULL REFERENCES policy_versions(id),
    listing_id uuid REFERENCES listings(id),
    exchange_id uuid REFERENCES exchanges(id),
    purpose text NOT NULL,
    accepted_at timestamptz NOT NULL DEFAULT now()
    );
    
    -- FR021–022 + October decisions: One document per review version; originals are encrypted object references, never donor-visible.
    CREATE TABLE identity_evidence (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    submitted_by uuid NOT NULL REFERENCES accounts(id),
    representation_id uuid REFERENCES representations(id),
    document_kind text NOT NULL CHECK (document_kind IN ('utility_bill','government_id')),
    restricted_object_key text,
    review_state text NOT NULL DEFAULT 'pending' CHECK (review_state IN ('pending','approved','rejected','revoked','deleted')),
    reviewer_id uuid REFERENCES accounts(id),
    verification_provider text,
    provider_reference text,
    reviewed_at timestamptz,
    valid_until timestamptz,
    policy_id uuid NOT NULL REFERENCES policy_versions(id),
    replaces_evidence_id uuid REFERENCES identity_evidence(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    purge_due_at timestamptz,
    deleted_at timestamptz,
    CHECK (review_state <> 'approved' OR ((reviewer_id IS NOT NULL OR verification_provider IS NOT NULL) AND reviewed_at IS NOT NULL AND valid_until IS NOT NULL AND valid_until > reviewed_at))
    );
    
    -- FR021–022: Per-field provenance; encrypted values only. No DOB, document number or financial fields.
    CREATE TABLE borrower_fields (
    evidence_id uuid NOT NULL REFERENCES identity_evidence(id),
    field_name text NOT NULL CHECK (field_name IN ('first_name','last_name','home_address','zip_code')),
    value_ciphertext bytea NOT NULL,
    key_version text NOT NULL,
    source text NOT NULL CHECK (source IN ('document','user_entered','verified_contact')),
    verification text NOT NULL CHECK (verification IN ('unverified','reviewed_against_evidence','contact_verified')),
    verified_at timestamptz,
    PRIMARY KEY (evidence_id,field_name),
    CHECK (verification='unverified' OR verified_at IS NOT NULL)
    );
    
    -- FR022: Request-specific named donor grant; replacing evidence requires a new consent.
    CREATE TABLE disclosure_grants (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    exchange_id uuid NOT NULL REFERENCES exchanges(id),
    evidence_id uuid NOT NULL REFERENCES identity_evidence(id),
    consented_by uuid NOT NULL REFERENCES accounts(id),
    donor_id uuid NOT NULL REFERENCES accounts(id),
    consent_policy_id uuid NOT NULL REFERENCES policy_versions(id),
    allowed_fields text[] NOT NULL,
    granted_at timestamptz NOT NULL DEFAULT now(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    CHECK (expires_at > granted_at),
    CHECK (cardinality(allowed_fields)>0 AND allowed_fields <@ ARRAY['first_name','last_name','zip_code']::text[])
    );
    
    -- FR022, NFR004: Log every allowed or denied private view without copying private values.
    CREATE TABLE sensitive_access_events (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    actor_id uuid NOT NULL REFERENCES accounts(id),
    grant_id uuid REFERENCES disclosure_grants(id),
    evidence_id uuid REFERENCES identity_evidence(id),
    purpose text NOT NULL,
    allowed boolean NOT NULL,
    field_names text[] NOT NULL DEFAULT '{}',
    occurred_at timestamptz NOT NULL DEFAULT now()
    );
    
    -- FR013, FR030, FR040, DEC04: Private reports and support/recovery cases; permits unauthenticated support entry.
    CREATE TABLE cases (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    reporter_id uuid REFERENCES accounts(id),
    listing_id uuid REFERENCES listings(id),
    exchange_id uuid REFERENCES exchanges(id),
    case_type text NOT NULL CHECK (case_type IN ('unsafe','recall','payment_demand','harassment','privacy','failed_pickup','non_return','transport','recovery','help')),
    owner_id uuid NOT NULL REFERENCES accounts(id),
    severity text NOT NULL CHECK (severity IN ('urgent','standard')),
    state text NOT NULL DEFAULT 'open' CHECK (state IN ('open','acknowledged','investigating','resolved','closed')),
    details_ciphertext bytea,
    next_action text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    acknowledged_at timestamptz,
    closed_at timestamptz,
    closure_reason text
    );
    
    -- FR013, FR030: Restricted case history including recovery decisions and escalation.
    CREATE TABLE case_actions (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    case_id uuid NOT NULL REFERENCES cases(id),
    actor_id uuid NOT NULL REFERENCES accounts(id),
    action text NOT NULL,
    notes_ciphertext bytea,
    created_at timestamptz NOT NULL DEFAULT now()
    );
    
    -- FR013, FR025, FR038: Independent item/account holds override normal availability.
    CREATE TABLE restrictions (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    listing_id uuid REFERENCES listings(id),
    account_id uuid REFERENCES accounts(id),
    case_id uuid REFERENCES cases(id),
    reason text NOT NULL CHECK (reason IN ('safety','recall','security','policy')),
    applied_by uuid NOT NULL REFERENCES accounts(id),
    applied_at timestamptz NOT NULL DEFAULT now(),
    released_by uuid REFERENCES accounts(id),
    released_at timestamptz,
    CHECK ((listing_id IS NOT NULL)::integer + (account_id IS NOT NULL)::integer = 1),
    CHECK ((released_at IS NULL) = (released_by IS NULL))
    );
    
    -- FR025–026, FR030, FR036: Hashed expiring credentials and generation binding; never public raw tokens.
    CREATE TABLE action_tokens (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    account_id uuid REFERENCES accounts(id),
    exchange_id uuid REFERENCES exchanges(id),
    case_id uuid REFERENCES cases(id),
    purpose text NOT NULL,
    token_digest bytea NOT NULL UNIQUE,
    allocation_generation integer,
    expires_at timestamptz NOT NULL,
    used_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (expires_at > created_at)
    );
    
    -- FR018, FR026–027: Append-only separate OTP/routine/email consent events; STOP must suppress dispatch.
    CREATE TABLE consent_events (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    account_id uuid NOT NULL REFERENCES accounts(id),
    contact_id uuid NOT NULL REFERENCES account_contacts(id),
    purpose text NOT NULL CHECK (purpose IN ('otp','routine_sms','email_notifications','email_marketing')),
    action text NOT NULL CHECK (action IN ('granted','withdrawn','stop','reset')),
    policy_id uuid REFERENCES policy_versions(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    idempotency_key text NOT NULL UNIQUE
    );
    
    -- FR027: Structured tasks/notices only; no in-account conversation fallback.
    CREATE TABLE account_notices (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    account_id uuid NOT NULL REFERENCES accounts(id),
    exchange_id uuid REFERENCES exchanges(id),
    listing_id uuid REFERENCES listings(id),
    notice_type text NOT NULL,
    reason_code text,
    due_at timestamptz,
    read_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now(),
    idempotency_key text NOT NULL UNIQUE
    );
    
    -- FR018, UJ001: Completion/return follow-up counter; physical outcomes remain independent.
    CREATE TABLE followup_cycles (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    exchange_id uuid NOT NULL REFERENCES exchanges(id),
    kind text NOT NULL CHECK (kind IN ('handoff','return')),
    state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','cancelled','answered','moderator_action_due','closed')),
    next_due_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT now()
    );
    
    -- FR009, FR018, FR036, DEC05: Transactional outbox. Templates/reference IDs only; no private text in payload.
    CREATE TABLE message_jobs (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    recipient_id uuid NOT NULL REFERENCES accounts(id),
    contact_id uuid NOT NULL REFERENCES account_contacts(id),
    exchange_id uuid REFERENCES exchanges(id),
    followup_cycle_id uuid REFERENCES followup_cycles(id),
    followup_attempt smallint CHECK (followup_attempt BETWEEN 1 AND 3),
    template_code text NOT NULL,
    state text NOT NULL DEFAULT 'queued' CHECK (state IN ('queued','claimed','sent','failed','cancelled','suppressed')),
    due_at timestamptz NOT NULL,
    claimed_until timestamptz,
    sent_at timestamptz,
    idempotency_key text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (followup_cycle_id,followup_attempt),
    CHECK ((followup_cycle_id IS NULL) = (followup_attempt IS NULL))
    );
    
    -- FR018: Each gateway dispatch is durable; retries count toward the follow-up cap.
    CREATE TABLE message_attempts (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    job_id uuid NOT NULL REFERENCES message_jobs(id),
    attempt_no integer NOT NULL CHECK (attempt_no > 0),
    provider text NOT NULL,
    provider_message_id text,
    state text NOT NULL CHECK (state IN ('sending','accepted','delivered','failed','unknown')),
    error_code text,
    attempted_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (job_id,attempt_no),
    UNIQUE (provider,provider_message_id)
    );
    
    -- FR018: Deduplicate callbacks; persist only normalized status, not raw sensitive bodies.
    CREATE TABLE gateway_events (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    provider text NOT NULL,
    provider_event_id text NOT NULL,
    attempt_id uuid REFERENCES message_attempts(id),
    event_type text NOT NULL,
    received_at timestamptz NOT NULL DEFAULT now(),
    processed_at timestamptz,
    UNIQUE (provider,provider_event_id)
    );
    
    -- FR009, DEC05: Encrypted listing-linked SMS drafts/history; transmission blocked until DEC05 approval.
    CREATE TABLE private_messages (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    exchange_id uuid NOT NULL REFERENCES exchanges(id),
    sender_id uuid NOT NULL REFERENCES accounts(id),
    recipient_id uuid NOT NULL REFERENCES accounts(id),
    body_ciphertext bytea NOT NULL,
    key_version text NOT NULL,
    state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','queued','sent','failed','received')),
    messaging_policy_id uuid REFERENCES policy_versions(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    CHECK (sender_id <> recipient_id),
    CHECK (state='draft' OR messaging_policy_id IS NOT NULL)
    );
    
    -- FR015–016, FR037: Reviewed directory; no implied partnership or transport availability.
    CREATE TABLE resources (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    name text NOT NULL,
    service_type text NOT NULL CHECK (service_type IN ('donation','loan','mixed_exchange','referral_only')),
    service_area text NOT NULL,
    cost_model text NOT NULL,
    restrictions text,
    official_url text NOT NULL,
    official_contact text,
    reviewer_id uuid REFERENCES accounts(id),
    verification_provider text,
    provider_reference text,
    reviewed_at timestamptz,
    published boolean NOT NULL DEFAULT false,
    CHECK (NOT published OR (reviewer_id IS NOT NULL AND reviewed_at IS NOT NULL))
    );
    
    -- FR017: Agreed assistance/referral roles; distinct from unconfirmed directory entries.
    CREATE TABLE organization_participation (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    organization_name text NOT NULL,
    agreed_role text NOT NULL,
    contact_ciphertext bytea,
    agreed_at timestamptz NOT NULL,
    ended_at timestamptz,
    public_listing_permission boolean NOT NULL DEFAULT false
    );
    
    -- FR040: Structured reasons only, no medical/household narrative.
    CREATE TABLE transport_barriers (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    exchange_id uuid NOT NULL REFERENCES exchanges(id),
    reported_by uuid NOT NULL REFERENCES accounts(id),
    stage text NOT NULL CHECK (stage IN ('before_reservation','after_reservation')),
    reason text NOT NULL CHECK (reason IN ('no_transport','accessibility','schedule','other')),
    resource_id uuid REFERENCES resources(id),
    recorded_at timestamptz NOT NULL DEFAULT now()
    );
    
    -- DEC03, NFR004: No default durations; approved schedule required before protected data collection.
    CREATE TABLE retention_rules (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    data_class text NOT NULL,
    policy_id uuid NOT NULL REFERENCES policy_versions(id),
    trigger_event text NOT NULL,
    retain_for interval NOT NULL CHECK (retain_for >= interval '0'),
    UNIQUE (data_class,policy_id)
    );
    
    -- DEC03, FR013: Explicit incident hold and release; subject reference validated by retention service.
    CREATE TABLE retention_holds (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    case_id uuid NOT NULL REFERENCES cases(id),
    data_class text NOT NULL,
    record_id uuid NOT NULL,
    created_by uuid NOT NULL REFERENCES accounts(id),
    created_at timestamptz NOT NULL DEFAULT now(),
    released_at timestamptz
    );
    
    -- DEC03, FR036: Object/record deletion with completion proof; backup expiry follows approved schedule.
    CREATE TABLE deletion_jobs (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    rule_id uuid NOT NULL REFERENCES retention_rules(id),
    record_id uuid NOT NULL,
    due_at timestamptz NOT NULL,
    state text NOT NULL DEFAULT 'queued' CHECK (state IN ('queued','held','running','complete','failed')),
    completed_at timestamptz,
    proof_digest text,
    idempotency_key text NOT NULL UNIQUE
    );
    
    -- FR036, NFR003–004: Append-only redacted action history; avoid old/new JSON containing private values.
    CREATE TABLE audit_events (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    actor_id uuid REFERENCES accounts(id),
    action text NOT NULL,
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    reason_code text,
    correlation_id uuid NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT now()
    );
    
    -- FR028: Append-only attempts for rolling limits; approved thresholds enforced under account lock.
    CREATE TABLE activity_events (
    id uuid PRIMARY KEY DEFAULT uuidv7(),
    account_id uuid NOT NULL REFERENCES accounts(id),
    action text NOT NULL,
    accepted boolean NOT NULL,
    policy_id uuid REFERENCES policy_versions(id),
    occurred_at timestamptz NOT NULL DEFAULT now(),
    idempotency_key text NOT NULL UNIQUE
    );
    
    ALTER TABLE listings ADD FOREIGN KEY (id,current_revision_id) REFERENCES listing_revisions(listing_id,id) DEFERRABLE INITIALLY DEFERRED;
    ALTER TABLE listings ADD FOREIGN KEY (id,approved_revision_id) REFERENCES listing_revisions(listing_id,id) DEFERRABLE INITIALLY DEFERRED;
    CREATE UNIQUE INDEX one_live_mobile_per_account ON account_contacts(account_id) WHERE kind='mobile' AND revoked_at IS NULL;
    CREATE UNIQUE INDEX one_live_phone_owner ON account_contacts(lookup_hmac) WHERE kind='mobile' AND revoked_at IS NULL;
    CREATE UNIQUE INDEX one_active_allocation_per_item ON exchanges(listing_id) WHERE state IN ('pending','offered','reserved','loaned');
    CREATE INDEX exchange_requester_history ON exchanges(requester_id,requested_at DESC);
    CREATE INDEX exchange_deadlines ON exchanges(pending_expires_at) WHERE state='pending';
    CREATE INDEX offer_deadlines ON exchanges(offer_expires_at) WHERE state='offered';
    CREATE INDEX queued_messages ON message_jobs(due_at) WHERE state='queued';
    CREATE INDEX active_listing_holds ON restrictions(listing_id) WHERE released_at IS NULL;
    CREATE INDEX active_account_holds ON restrictions(account_id) WHERE released_at IS NULL;
    CREATE INDEX donor_inventory ON listings(donor_id,created_at DESC);
    CREATE INDEX activity_window ON activity_events(account_id,action,occurred_at);
    CREATE INDEX contact_consent_history ON consent_events(contact_id,purpose,occurred_at DESC,id DESC);
    CREATE INDEX listing_search ON listing_revisions USING gin(to_tsvector('english',title || ' ' || description));
    INSERT INTO pilot_controls(singleton) VALUES (true);
    INSERT INTO categories(code,name) VALUES ('walkers','Walkers'),('canes','Canes'),('shower_chairs','Shower chairs'),('commodes','Commodes'),('crutches','Crutches'),('manual_wheelchairs','Manual wheelchairs'),('other','Other');
    
    -- Row-level checks supplement (not replace) authenticated Rails services.
    CREATE FUNCTION frozen_revision() RETURNS trigger LANGUAGE plpgsql SET search_path=freedme,pg_catalog AS $$
    BEGIN
     IF OLD.submitted_at IS NOT NULL THEN
      RAISE EXCEPTION 'Submitted revisions are immutable; create a new revision';
     END IF;
     RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
    END $$;
    CREATE TRIGGER freeze_submitted_revision BEFORE UPDATE OR DELETE ON listing_revisions FOR EACH ROW EXECUTE FUNCTION frozen_revision();
    
    CREATE FUNCTION prevent_history_mutation() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN RAISE EXCEPTION 'History is append-only; approved retention maintenance uses a separate owner-controlled process'; END $$;
    CREATE TRIGGER audit_append_only BEFORE UPDATE OR DELETE ON audit_events FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();
    CREATE TRIGGER lifecycle_append_only BEFORE UPDATE OR DELETE ON exchange_events FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();
    CREATE TRIGGER consent_append_only BEFORE UPDATE OR DELETE ON consent_events FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();
    CREATE TRIGGER agreement_immutable BEFORE UPDATE OR DELETE ON agreements FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();
    
    CREATE FUNCTION evidence_collection_gate() RETURNS trigger LANGUAGE plpgsql SET search_path=freedme,pg_catalog AS $$
    BEGIN
     IF NOT EXISTS (SELECT 1 FROM pilot_controls c JOIN policy_versions p ON p.id=c.privacy_policy_id
       WHERE c.evidence_collection_enabled AND p.approved_at IS NOT NULL AND p.effective_at <= now()) THEN
      RAISE EXCEPTION 'Identity evidence collection is disabled pending approved privacy controls';
     END IF;
     RETURN NEW;
    END $$;
    CREATE TRIGGER evidence_gate BEFORE INSERT ON identity_evidence FOR EACH ROW EXECUTE FUNCTION evidence_collection_gate();
    
    CREATE FUNCTION guard_publication() RETURNS trigger LANGUAGE plpgsql SET search_path=freedme,pg_catalog AS $$
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
    CREATE TRIGGER publication_guard BEFORE INSERT OR UPDATE ON listings FOR EACH ROW EXECUTE FUNCTION guard_publication();
    
    CREATE FUNCTION guard_exchange() RETURNS trigger LANGUAGE plpgsql SET search_path=freedme,pg_catalog AS $$
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
    CREATE TRIGGER exchange_guard BEFORE INSERT OR UPDATE ON exchanges FOR EACH ROW EXECUTE FUNCTION guard_exchange();
    
    -- Verified gifts AND loans: create exchange + consent in one transaction; check at COMMIT.
    -- October user revision supersedes the older loan-only collection rule.
    CREATE FUNCTION validate_verified_request() RETURNS trigger LANGUAGE plpgsql SET search_path=freedme,pg_catalog AS $$
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
    CREATE CONSTRAINT TRIGGER request_identity_required AFTER INSERT OR UPDATE ON exchanges DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION validate_verified_request();
    
    -- Publication view has no contacts, precise ZIP, evidence, private messages or original object keys.
    -- It is deliberately NOT granted to PUBLIC; expose via the authenticated Rails API/public projection.
    CREATE VIEW available_listing_cards AS
    SELECT l.id,l.donor_id,a.display_name,r.title,r.description,c.category_id,r.offer_kind,r.loan_until,
     r.public_locality,r.condition_description,r.manufacturer,r.model,r.capacity_description,r.pickup_availability
    FROM listings l JOIN accounts a ON a.id=l.donor_id
    JOIN listing_revisions r ON r.id=l.approved_revision_id
    JOIN equipment_configurations c ON c.id=r.configuration_id
    WHERE l.status='available' AND l.current_revision_id=l.approved_revision_id AND a.status='active'
     AND l.availability_valid_until>now() AND c.allowed
     AND NOT EXISTS(SELECT 1 FROM exchanges e WHERE e.listing_id=l.id AND e.state IN ('pending','offered','reserved','loaned'))
     AND NOT EXISTS(SELECT 1 FROM restrictions h WHERE h.released_at IS NULL AND (h.listing_id=l.id OR h.account_id=l.donor_id));
    
    -- Counts are reservations, not people served or physical transfers. Dates are timestamptz, report in approved timezone.
    CREATE VIEW reservation_facts AS
    SELECT e.id AS exchange_id,e.listing_id,e.requester_id,e.representation_id,e.reserved_at,
     (e.reserved_at IS NOT NULL AND e.state NOT IN ('cancelled','closed_unavailable')) AS counts_as_success,
     (SELECT min(v.occurred_at) FROM exchange_events v WHERE v.exchange_id=e.id AND v.event_type='handoff_confirmed') AS handoff_confirmed_at,
     (SELECT min(v.occurred_at) FROM exchange_events v WHERE v.exchange_id=e.id AND v.event_type='return_confirmed') AS return_confirmed_at
    FROM exchanges e WHERE e.reserved_at IS NOT NULL;
    
    -- FR003: Preserve donation/request return path before account creation.
    -- A mobile OTP session is not an account. Delete expired sessions by approved retention policy.
    CREATE TABLE registration_sessions (
     id uuid PRIMARY KEY DEFAULT uuidv7(),
     challenge_id uuid NOT NULL REFERENCES auth_challenges(id),
     display_name text NOT NULL CHECK(length(trim(display_name)) BETWEEN 1 AND 80),
     approximate_location text NOT NULL CHECK(length(trim(approximate_location)) BETWEEN 1 AND 160),
     intended_action text NOT NULL CHECK(intended_action IN ('donate','request')),
     listing_id uuid REFERENCES listings(id),
     created_account_id uuid REFERENCES accounts(id),
     created_at timestamptz NOT NULL DEFAULT now(),
     expires_at timestamptz NOT NULL,
     CHECK(expires_at>created_at),
     CHECK(intended_action<>'request' OR listing_id IS NOT NULL)
    );
    
    -- Identity processing precedes donor-visible exchange creation. Drafts do not allocate inventory.
    CREATE TABLE request_intents (
     id uuid PRIMARY KEY DEFAULT uuidv7(),
     listing_id uuid NOT NULL REFERENCES listings(id),
     requester_id uuid NOT NULL REFERENCES accounts(id),
     representation_id uuid,
     evidence_id uuid REFERENCES identity_evidence(id),
     state text NOT NULL DEFAULT 'awaiting_evidence' CHECK(state IN ('awaiting_evidence','verifying','failed','verified','submitted','cancelled','expired')),
     exchange_id uuid UNIQUE REFERENCES exchanges(id),
     requested_end_date date,
     created_at timestamptz NOT NULL DEFAULT now(),
     expires_at timestamptz NOT NULL,
     idempotency_key uuid NOT NULL UNIQUE,
     FOREIGN KEY(representation_id,requester_id) REFERENCES representations(id,representative_id),
     CHECK(expires_at>created_at),
     CHECK((state='submitted')=(exchange_id IS NOT NULL))
    );
    CREATE INDEX pending_identity_intents ON request_intents(requester_id,created_at DESC);
    
    -- FR009/FR041: Q&A exists before a request. One row per question, grouped by item in UI.
    CREATE TABLE equipment_questions (
     id uuid PRIMARY KEY DEFAULT uuidv7(),
     listing_id uuid NOT NULL,
     donor_id uuid NOT NULL,
     requester_id uuid NOT NULL REFERENCES accounts(id),
     question_ciphertext bytea NOT NULL,
     answer_ciphertext bytea,
     key_version text NOT NULL,
     state text NOT NULL DEFAULT 'pending' CHECK(state IN ('pending','answered','withdrawn')),
     asked_at timestamptz NOT NULL DEFAULT now(),
     answered_at timestamptz,
     answered_by uuid REFERENCES accounts(id),
     idempotency_key uuid NOT NULL UNIQUE,
     FOREIGN KEY(listing_id,donor_id) REFERENCES listings(id,donor_id),
     CHECK(requester_id<>donor_id),
     CHECK((state='answered')=(answer_ciphertext IS NOT NULL)),
     CHECK((answer_ciphertext IS NULL)=(answered_at IS NULL)),
     CHECK((answer_ciphertext IS NULL)=(answered_by IS NULL)),
     CHECK(answered_by IS NULL OR answered_by=donor_id),
     CHECK(answered_at IS NULL OR answered_at>=asked_at)
    );
    CREATE INDEX donor_pending_questions ON equipment_questions(donor_id,asked_at) WHERE state='pending';
    CREATE INDEX requester_question_history ON equipment_questions(requester_id,listing_id,asked_at);
    ALTER TABLE message_jobs ADD COLUMN question_id uuid REFERENCES equipment_questions(id);
    ALTER TABLE message_jobs ADD COLUMN listing_id uuid REFERENCES listings(id);
    
    -- FR010/FR018 + October negotiation decision: immutable versioned proposals, separately accepted.
    CREATE TABLE handoff_proposals (
     id uuid PRIMARY KEY DEFAULT uuidv7(),
     exchange_id uuid NOT NULL REFERENCES exchanges(id),
     revision integer NOT NULL CHECK(revision>0),
     proposed_by uuid NOT NULL REFERENCES accounts(id),
     meeting_at timestamptz NOT NULL,
     display_timezone text NOT NULL DEFAULT 'America/Los_Angeles',
     public_location_ciphertext bytea NOT NULL,
     key_version text NOT NULL,
     created_at timestamptz NOT NULL DEFAULT now(),
     idempotency_key uuid NOT NULL UNIQUE,
     UNIQUE(exchange_id,revision),
     UNIQUE(id,exchange_id)
    );
    CREATE TABLE handoff_acceptances (
     proposal_id uuid PRIMARY KEY,
     exchange_id uuid NOT NULL,
     accepted_by uuid NOT NULL REFERENCES accounts(id),
     accepted_at timestamptz NOT NULL DEFAULT now(),
     FOREIGN KEY(proposal_id,exchange_id) REFERENCES handoff_proposals(id,exchange_id)
    );
    CREATE FUNCTION guard_handoff_proposal() RETURNS trigger LANGUAGE plpgsql SET search_path=freedme,pg_catalog AS $$
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
    CREATE TRIGGER handoff_proposal_guard BEFORE INSERT ON handoff_proposals FOR EACH ROW EXECUTE FUNCTION guard_handoff_proposal();
    CREATE FUNCTION guard_handoff_acceptance() RETURNS trigger LANGUAGE plpgsql SET search_path=freedme,pg_catalog AS $$
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
    CREATE TRIGGER handoff_acceptance_guard BEFORE INSERT ON handoff_acceptances FOR EACH ROW EXECUTE FUNCTION guard_handoff_acceptance();
    CREATE TRIGGER handoff_proposal_immutable BEFORE UPDATE OR DELETE ON handoff_proposals FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();
    CREATE TRIGGER handoff_acceptance_immutable BEFORE UPDATE OR DELETE ON handoff_acceptances FOR EACH ROW EXECUTE FUNCTION prevent_history_mutation();
    CREATE VIEW current_handoff_arrangements AS
    SELECT DISTINCT ON (p.exchange_id) p.*,a.accepted_by,a.accepted_at
    FROM handoff_proposals p LEFT JOIN handoff_acceptances a ON a.proposal_id=p.id
    ORDER BY p.exchange_id,p.revision DESC;
    
    -- FR043: Queue worker calls this periodically; one task per reservation, no inferred transfer.
    CREATE TABLE moderator_tasks (
     id uuid PRIMARY KEY DEFAULT uuidv7(),
     exchange_id uuid NOT NULL REFERENCES exchanges(id),
     kind text NOT NULL CHECK(kind IN('unconfirmed_handoff')),
     due_at timestamptz NOT NULL,
     state text NOT NULL DEFAULT 'open' CHECK(state IN('open','in_progress','resolved','cancelled')),
     assigned_to uuid REFERENCES accounts(id),
     donor_contacted_at timestamptz,
     recipient_contacted_at timestamptz,
     outcome text CHECK(outcome IN('handoff_confirmed','not_handed_off','unable_to_reach','cancelled')),
     notes_ciphertext bytea,
     resolved_at timestamptz,
     created_at timestamptz NOT NULL DEFAULT now(),
     UNIQUE(exchange_id,kind),
     CHECK((state IN('resolved','cancelled'))=(resolved_at IS NOT NULL)),
     CHECK(state<>'resolved' OR outcome IS NOT NULL)
    );
    CREATE INDEX moderator_work_queue ON moderator_tasks(due_at) WHERE state IN('open','in_progress');
    CREATE FUNCTION enqueue_handoff_followups(as_of timestamptz DEFAULT now()) RETURNS integer LANGUAGE plpgsql SET search_path=freedme,pg_catalog AS $$
    DECLARE n integer;
    BEGIN
     INSERT INTO moderator_tasks(exchange_id,kind,due_at)
     SELECT e.id,'unconfirmed_handoff',e.reserved_at+interval '168 hours' FROM exchanges e
     WHERE e.state='reserved' AND e.reserved_at+interval '168 hours'<=as_of
     AND NOT EXISTS(SELECT 1 FROM exchange_events v WHERE v.exchange_id=e.id AND v.event_type='handoff_confirmed')
     ON CONFLICT(exchange_id,kind) DO NOTHING;
     GET DIAGNOSTICS n=ROW_COUNT; RETURN n;
    END $$;
    
    -- FR044: Hiding an expired request is a participant display preference, not historical deletion.
    CREATE TABLE exchange_display_preferences (
     exchange_id uuid NOT NULL REFERENCES exchanges(id),
     account_id uuid NOT NULL REFERENCES accounts(id),
     hidden_at timestamptz,
     replaced_by_exchange_id uuid REFERENCES exchanges(id),
     PRIMARY KEY(exchange_id,account_id),
     CHECK(replaced_by_exchange_id IS DISTINCT FROM exchange_id)
    );
    
    -- FR011: Either participant confirms handoff; only donor confirms return.
    CREATE FUNCTION guard_transfer_event() RETURNS trigger LANGUAGE plpgsql SET search_path=freedme,pg_catalog AS $$
    DECLARE ex exchanges;
    BEGIN
     SELECT * INTO ex FROM exchanges WHERE id=NEW.exchange_id FOR UPDATE;
     IF NEW.event_type='handoff_confirmed' THEN
      IF NEW.actor_id IS NULL OR NEW.actor_id NOT IN(ex.donor_id,ex.requester_id) OR ex.state NOT IN('reserved','loaned','completed')
      THEN RAISE EXCEPTION 'Only a participant may confirm a reserved handoff'; END IF;
     ELSIF NEW.event_type='return_confirmed' THEN
      IF NEW.actor_id IS DISTINCT FROM ex.donor_id OR ex.state NOT IN('loaned','completed')
      THEN RAISE EXCEPTION 'Only donor may confirm loan return'; END IF;
     END IF;
     RETURN NEW;
    END $$;
    CREATE TRIGGER transfer_event_guard BEFORE INSERT ON exchange_events FOR EACH ROW EXECUTE FUNCTION guard_transfer_event();
    CREATE UNIQUE INDEX single_handoff_confirmation ON exchange_events(exchange_id) WHERE event_type='handoff_confirmed';
    CREATE UNIQUE INDEX single_return_confirmation ON exchange_events(exchange_id) WHERE event_type='return_confirmed';
    
    -- FR022: Private projection for a trusted API; actor must come from authenticated session,
    -- never from an unchecked client parameter. No PUBLIC execute grant is provided.
    CREATE FUNCTION read_donor_identity(actor uuid, requested_exchange uuid)
    RETURNS TABLE(field_name text,value_ciphertext bytea,key_version text)
    LANGUAGE plpgsql SET search_path=freedme,pg_catalog AS $$
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
    
    -- Minimal CMS supports Our Team without inventing names/contact details.
    CREATE TABLE team_profiles (
     id uuid PRIMARY KEY DEFAULT uuidv7(), display_name text NOT NULL,
     role_title text NOT NULL, biography text NOT NULL,
     photo_object_key text, sort_order integer NOT NULL DEFAULT 0,
     publication_consent_at timestamptz, published_at timestamptz,
     CHECK(published_at IS NULL OR publication_consent_at IS NOT NULL)
    );
    
    -- Template text versioning; worker resolves placeholders from authorized records at dispatch.
    CREATE TABLE notification_templates (
     code text NOT NULL, version integer NOT NULL CHECK(version>0),
     body text NOT NULL, approved_at timestamptz,
     PRIMARY KEY(code,version)
    );
    ALTER TABLE message_jobs ADD COLUMN template_version integer NOT NULL DEFAULT 1;
    ALTER TABLE message_jobs ADD FOREIGN KEY(template_code,template_version) REFERENCES notification_templates(code,version);
    INSERT INTO notification_templates(code,version,body) VALUES
    ('registration_welcome',1,'Welcome to FreeDME, {display_name}.'),
    ('listing_submitted',1,'Thank you for offering your equipment to a neighbor. Your listing is under review. You will be notified when it is published,'),
    ('request_received',1,'{verified_name} from {town} has requested your {item_title}. You may approve or decline the request. If the item is no longer available, please indicate “not available”. Please respond within 48 hours.'),
    ('donor_approval_ack',1,'The requester is notified of your approval as well as the proposed location and time for the hand-off. We will notify you when the requester accepts/rejects your offer'),
    ('request_approved',1,'Your request for the {item_title} has been approved by the donor. Please review the proposed pick up location and time and respond.'),
    ('request_declined',1,'Your request for “{item_title}” has been declined by the donor. You may review the inventory for similar items and make a new request.'),
    ('item_unavailable',1,'Your requested equipment ({item_title}) is no longer available. You may review the inventory for similar items and make a new request.'),
    ('question_received',1,'An interested recipient has a question about your equipment. Open My Activity to answer.'),
    ('question_answered',1,'The donor has answered your question. Open My Activity to view the answer.'),
    ('handoff_proposed',1,'A new pickup time and location have been suggested. Open My Activity to review.'),
    ('handoff_accepted',1,'Your proposed pickup arrangement has been accepted. Open My Activity for details.');
    
    REVOKE ALL ON ALL TABLES IN SCHEMA freedme FROM PUBLIC;
    REVOKE ALL ON ALL FUNCTIONS IN SCHEMA freedme FROM PUBLIC;
    ALTER DEFAULT PRIVILEGES IN SCHEMA freedme REVOKE ALL ON TABLES FROM PUBLIC;
    ALTER DEFAULT PRIVILEGES IN SCHEMA freedme REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
  FREEDME_SCHEMA_SQL

  def up
    unless connection.adapter_name == "PostgreSQL"
      raise ActiveRecord::MigrationError, "FreeDME requires PostgreSQL 18 or later"
    end
    if connection.select_value("SHOW server_version_num").to_i < 180000
      raise ActiveRecord::MigrationError, "FreeDME requires PostgreSQL 18 or later"
    end
    if connection.select_value("SELECT to_regnamespace('freedme')::text")
      raise ActiveRecord::MigrationError,
        "Schema freedme already exists. This is a fresh-install baseline, not a v0.1 upgrade."
    end

    previous_search_path = connection.select_value("SHOW search_path")
    begin
      execute SCHEMA_SQL
    ensure
      # Rails still needs to record the migration in its original metadata schema.
      # On SQL failure PostgreSQL has aborted the transaction; the Rails rollback
      # restores SET LOCAL automatically, so don't mask the original exception.
      unless $!
        execute "SELECT set_config('search_path', #{connection.quote(previous_search_path)}, true)"
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "FreeDME contains identity, consent, and exchange history. Restore a backup or write a reviewed forward migration."
  end
end
