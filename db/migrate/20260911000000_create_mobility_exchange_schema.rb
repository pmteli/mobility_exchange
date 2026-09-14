# frozen_string_literal: true

# Rails 8.x / PostgreSQL 18. Run with: bin/rails db:migrate
# Keep Rails' default transactional migrations enabled.
# SQL is embedded to make this migration self-contained and reproducible.
class CreateMobilityExchangeSchema < ActiveRecord::Migration[8.0]
  def up
    unless connection.adapter_name == "PostgreSQL"
      raise ActiveRecord::MigrationError, "Mobility Exchange requires PostgreSQL 18"
    end

    version = connection.select_value("SHOW server_version_num").to_i
    unless version >= 180_000 && version < 190_000
      raise ActiveRecord::MigrationError, "This migration targets PostgreSQL 18.x"
    end

    existing = connection.select_value(
      "SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'mobility_exchange'"
    )
    if existing
      raise ActiveRecord::MigrationError,
        "mobility_exchange already exists; use a new database or a reviewed upgrade migration"
    end

    original_search_path = connection.select_value("SHOW search_path")
    execute <<~'SQL'
      -- Mobility Exchange • PostgreSQL 18 • Initial schema
      -- New database only; no extensions required. Existing opaque TEXT IDs retained.
      -- Business writes MUST run in SERIALIZABLE transactions; retry SQLSTATE 40001.
      -- This migration creates its own namespace and does not alter the SQLite source.
      SET LOCAL TIME ZONE 'UTC';
      CREATE SCHEMA mobility_exchange;
      SET LOCAL search_path = mobility_exchange, pg_catalog;
      
      
      CREATE TABLE schema_versions (version INTEGER PRIMARY KEY, applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP);
      
      -- Case-insensitive account email uniqueness without an extension.
      
      
      CREATE TABLE users (
       id TEXT PRIMARY KEY NOT NULL, auth_subject TEXT UNIQUE NOT NULL,
       email TEXT NOT NULL, first_name TEXT NOT NULL, last_name TEXT NOT NULL,
       phone TEXT, account_status TEXT NOT NULL DEFAULT 'pending' CHECK(account_status IN ('pending','active','suspended','archived')),
       email_verified_at TIMESTAMPTZ, last_login_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, archived_at TIMESTAMPTZ
      );
      
      CREATE TABLE roles (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL UNIQUE);
      
      CREATE TABLE permissions (id TEXT PRIMARY KEY NOT NULL, description TEXT NOT NULL);
      
      CREATE TABLE role_permissions (role_id TEXT NOT NULL REFERENCES roles(id), permission_id TEXT NOT NULL REFERENCES permissions(id), PRIMARY KEY(role_id,permission_id));
      
      CREATE TABLE user_roles (user_id TEXT NOT NULL REFERENCES users(id), role_id TEXT NOT NULL REFERENCES roles(id), assigned_by TEXT NOT NULL REFERENCES users(id), assigned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(user_id,role_id));
      
      CREATE TABLE user_permission_grants (user_id TEXT NOT NULL REFERENCES users(id), permission_id TEXT NOT NULL REFERENCES permissions(id), granted_by TEXT NOT NULL REFERENCES users(id), expires_at TIMESTAMPTZ, PRIMARY KEY(user_id,permission_id));
      
      CREATE TABLE locations (
       id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, address_line1 TEXT, address_line2 TEXT, city TEXT, region TEXT, postal_code TEXT, country_code TEXT NOT NULL DEFAULT 'US',
       timezone TEXT NOT NULL DEFAULT 'America/Los_Angeles', latitude DOUBLE PRECISION CHECK(latitude BETWEEN -90 AND 90), longitude DOUBLE PRECISION CHECK(longitude BETWEEN -180 AND 180),
       phone TEXT, email TEXT, instructions TEXT, pickup_enabled BOOLEAN NOT NULL DEFAULT FALSE, dropoff_enabled BOOLEAN NOT NULL DEFAULT FALSE,
       status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','temporarily_unavailable','archived'))
      );
      
      CREATE TABLE location_hours (id TEXT PRIMARY KEY NOT NULL, location_id TEXT NOT NULL REFERENCES locations(id), weekday INTEGER NOT NULL CHECK(weekday BETWEEN 0 AND 6), opens_local TIME WITHOUT TIME ZONE NOT NULL, closes_local TIME WITHOUT TIME ZONE NOT NULL, CHECK(opens_local < closes_local), UNIQUE(location_id,weekday,opens_local));
      
      CREATE TABLE location_closures (id TEXT PRIMARY KEY NOT NULL, location_id TEXT NOT NULL REFERENCES locations(id), starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NOT NULL, reason TEXT NOT NULL, CHECK(ends_at > starts_at));
      
      CREATE TABLE donors (
       id TEXT PRIMARY KEY NOT NULL, user_id TEXT UNIQUE REFERENCES users(id), first_name TEXT NOT NULL, last_name TEXT NOT NULL, organization TEXT,
       email TEXT, phone TEXT, address_line1 TEXT, address_line2 TEXT, city TEXT, region TEXT, postal_code TEXT,
       preferred_contact TEXT CHECK(preferred_contact IN ('email','phone','none')), private_notes TEXT, archived_at TIMESTAMPTZ,
       created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE recipients (
       id TEXT PRIMARY KEY NOT NULL, user_id TEXT UNIQUE REFERENCES users(id), first_name TEXT NOT NULL, last_name TEXT NOT NULL, email TEXT, phone TEXT,
       address_line1 TEXT, address_line2 TEXT, city TEXT, region TEXT, postal_code TEXT, date_of_birth DATE, private_notes TEXT, archived_at TIMESTAMPTZ,
       created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE volunteers (
       user_id TEXT PRIMARY KEY NOT NULL REFERENCES users(id), approval_status TEXT NOT NULL DEFAULT 'pending' CHECK(approval_status IN ('pending','approved','rejected','inactive')),
       approved_by TEXT REFERENCES users(id), approved_at TIMESTAMPTZ, emergency_contact_name TEXT, emergency_contact_phone TEXT, skills TEXT, private_notes TEXT
      );
      
      CREATE TABLE equipment_categories (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL UNIQUE, active BOOLEAN NOT NULL DEFAULT TRUE);
      
      CREATE TABLE equipment_types (id TEXT PRIMARY KEY NOT NULL, category_id TEXT NOT NULL REFERENCES equipment_categories(id), name TEXT NOT NULL, active BOOLEAN NOT NULL DEFAULT TRUE, UNIQUE(category_id,name));
      
      CREATE TABLE inventory_statuses (code TEXT PRIMARY KEY NOT NULL, label TEXT NOT NULL UNIQUE, sort_order INTEGER NOT NULL, system_managed BOOLEAN NOT NULL DEFAULT FALSE);
      
      CREATE TABLE inventory_transitions (from_status TEXT NOT NULL REFERENCES inventory_statuses(code), to_status TEXT NOT NULL REFERENCES inventory_statuses(code), PRIMARY KEY(from_status,to_status), CHECK(from_status <> to_status));
      
      CREATE TABLE files (
       id TEXT PRIMARY KEY NOT NULL, object_key TEXT NOT NULL UNIQUE, original_filename TEXT NOT NULL, mime_type TEXT NOT NULL,
       byte_size BIGINT NOT NULL CHECK(byte_size >= 0), sha256 TEXT NOT NULL CHECK(length(sha256)=64),
       uploaded_by TEXT REFERENCES users(id), scan_status TEXT NOT NULL DEFAULT 'pending' CHECK(scan_status IN ('pending','clean','rejected')),
       created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, deleted_at TIMESTAMPTZ
      );
      
      CREATE TABLE intake_submissions (
       id TEXT PRIMARY KEY NOT NULL, reference_number TEXT NOT NULL UNIQUE, donor_id TEXT NOT NULL REFERENCES donors(id), submitted_by TEXT REFERENCES users(id),
       status TEXT NOT NULL DEFAULT 'draft' CHECK(status IN ('draft','submitted','under_review','approved','scheduled','received','completed','rejected','cancelled')),
       preferred_location_id TEXT REFERENCES locations(id), submitted_at TIMESTAMPTZ, reviewed_by TEXT REFERENCES users(id), reviewed_at TIMESTAMPTZ, rejection_reason TEXT,
       private_notes TEXT, archived_at TIMESTAMPTZ, created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
       CHECK(status <> 'rejected' OR length(trim(rejection_reason))>0 AND rejection_reason IS NOT NULL)
      );
      
      CREATE TABLE intake_items (
       id TEXT PRIMARY KEY NOT NULL, intake_id TEXT NOT NULL REFERENCES intake_submissions(id), type_id TEXT NOT NULL REFERENCES equipment_types(id),
       name TEXT NOT NULL, manufacturer TEXT, model TEXT, serial_number TEXT, description TEXT, condition TEXT NOT NULL CHECK(condition IN ('new','excellent','good','fair','poor','unknown')),
       quantity INTEGER NOT NULL DEFAULT 1 CHECK(quantity > 0), approximate_age_years DOUBLE PRECISION CHECK(approximate_age_years >= 0),
       height_cm DOUBLE PRECISION CHECK(height_cm > 0), length_cm DOUBLE PRECISION CHECK(length_cm > 0), width_cm DOUBLE PRECISION CHECK(width_cm > 0), weight_kg DOUBLE PRECISION CHECK(weight_kg > 0), notes TEXT
      );
      
      CREATE TABLE intake_item_files (intake_item_id TEXT NOT NULL REFERENCES intake_items(id), file_id TEXT NOT NULL REFERENCES files(id), purpose TEXT NOT NULL CHECK(purpose IN ('front','back','side','serial','damage','accessory','other')), PRIMARY KEY(intake_item_id,file_id));
      
      CREATE TABLE purchases (
       id TEXT PRIMARY KEY NOT NULL, vendor_name TEXT NOT NULL, purchased_on DATE NOT NULL, currency TEXT NOT NULL CHECK(length(currency)=3), funding_source TEXT,
       receipt_file_id TEXT REFERENCES files(id), created_by TEXT NOT NULL REFERENCES users(id), notes TEXT
      );
      
      CREATE TABLE purchase_lines (id TEXT PRIMARY KEY NOT NULL, purchase_id TEXT NOT NULL REFERENCES purchases(id), type_id TEXT NOT NULL REFERENCES equipment_types(id), quantity INTEGER NOT NULL CHECK(quantity>0), unit_cost_minor BIGINT NOT NULL CHECK(unit_cost_minor>=0), description TEXT);
      
      CREATE TABLE equipment (
       id TEXT PRIMARY KEY NOT NULL, inventory_number TEXT NOT NULL UNIQUE, type_id TEXT NOT NULL REFERENCES equipment_types(id),
       name TEXT NOT NULL, manufacturer TEXT, model TEXT, serial_number TEXT, description TEXT, color TEXT,
       condition TEXT NOT NULL CHECK(condition IN ('new','excellent','good','fair','poor','unknown')),
       height_cm DOUBLE PRECISION CHECK(height_cm>0), length_cm DOUBLE PRECISION CHECK(length_cm>0), width_cm DOUBLE PRECISION CHECK(width_cm>0), weight_kg DOUBLE PRECISION CHECK(weight_kg>0), max_user_weight_kg DOUBLE PRECISION CHECK(max_user_weight_kg>0),
       acquisition_kind TEXT NOT NULL CHECK(acquisition_kind IN ('donation','purchase','legacy')),
       intake_item_id TEXT REFERENCES intake_items(id), purchase_line_id TEXT REFERENCES purchase_lines(id),
       status_code TEXT NOT NULL DEFAULT 'received' REFERENCES inventory_statuses(code), location_id TEXT NOT NULL REFERENCES locations(id), storage_position TEXT,
       assigned_volunteer_id TEXT REFERENCES volunteers(user_id), received_at TIMESTAMPTZ NOT NULL,
       public_notes TEXT, private_notes TEXT, disposition_reason TEXT,
       created_by TEXT NOT NULL REFERENCES users(id), updated_by TEXT NOT NULL REFERENCES users(id),
       created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, archived_at TIMESTAMPTZ,
       CHECK((acquisition_kind='donation' AND intake_item_id IS NOT NULL AND purchase_line_id IS NULL) OR (acquisition_kind='purchase' AND purchase_line_id IS NOT NULL AND intake_item_id IS NULL) OR (acquisition_kind='legacy' AND intake_item_id IS NULL AND purchase_line_id IS NULL)),
       CHECK(status_code <> 'disposal' OR (disposition_reason IS NOT NULL AND length(trim(disposition_reason))>0))
      );
      
      CREATE TABLE equipment_files (equipment_id TEXT NOT NULL REFERENCES equipment(id), file_id TEXT NOT NULL REFERENCES files(id), purpose TEXT NOT NULL CHECK(purpose IN ('photo','manual','inspection','repair','other')), public_approved BOOLEAN NOT NULL DEFAULT FALSE, sort_order INTEGER NOT NULL DEFAULT 0, approved_by TEXT REFERENCES users(id), PRIMARY KEY(equipment_id,file_id), CHECK(public_approved = FALSE OR (purpose='photo' AND approved_by IS NOT NULL)));
      
      CREATE TABLE processing_events (
       id TEXT PRIMARY KEY NOT NULL, equipment_id TEXT NOT NULL REFERENCES equipment(id), kind TEXT NOT NULL CHECK(kind IN ('inspection','sanitization','repair','preparation','disposal')),
       outcome TEXT NOT NULL CHECK(outcome IN ('passed','failed','completed','needs_repair','not_suitable')), performed_by TEXT NOT NULL REFERENCES users(id),
       performed_at TIMESTAMPTZ NOT NULL, notes TEXT NOT NULL, checklist_json JSONB,
       supersedes_id TEXT UNIQUE REFERENCES processing_events(id), created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE equipment_status_history (
       id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, equipment_id TEXT NOT NULL REFERENCES equipment(id), from_status TEXT REFERENCES inventory_statuses(code), to_status TEXT NOT NULL REFERENCES inventory_statuses(code),
       actor_id TEXT NOT NULL REFERENCES users(id), changed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE appointment_slots (
       id TEXT PRIMARY KEY NOT NULL, location_id TEXT NOT NULL REFERENCES locations(id), kind TEXT NOT NULL CHECK(kind IN ('dropoff','pickup')),
       starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NOT NULL, capacity INTEGER NOT NULL CHECK(capacity>0), cancelled_at TIMESTAMPTZ, created_by TEXT NOT NULL REFERENCES users(id), CHECK(ends_at>starts_at)
      );
      
      CREATE TABLE equipment_requests (
       id TEXT PRIMARY KEY NOT NULL, reference_number TEXT NOT NULL UNIQUE, recipient_id TEXT NOT NULL REFERENCES recipients(id), requested_by TEXT REFERENCES users(id),
       status TEXT NOT NULL DEFAULT 'submitted' CHECK(status IN ('submitted','under_review','approved','rejected','cancelled','completed')),
       submitted_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, reviewed_by TEXT REFERENCES users(id), reviewed_at TIMESTAMPTZ, rejection_reason TEXT, private_notes TEXT, archived_at TIMESTAMPTZ,
       UNIQUE(id,recipient_id)
      );
      
      CREATE TABLE request_items (id TEXT PRIMARY KEY NOT NULL, request_id TEXT NOT NULL REFERENCES equipment_requests(id), equipment_id TEXT NOT NULL REFERENCES equipment(id), UNIQUE(request_id,equipment_id), UNIQUE(id,request_id,equipment_id));
      
      CREATE TABLE appointments (
       id TEXT PRIMARY KEY NOT NULL, slot_id TEXT NOT NULL REFERENCES appointment_slots(id), intake_id TEXT REFERENCES intake_submissions(id), request_id TEXT REFERENCES equipment_requests(id),
       status TEXT NOT NULL DEFAULT 'booked' CHECK(status IN ('booked','completed','cancelled','no_show')), notes TEXT,
       created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, CHECK((intake_id IS NOT NULL) <> (request_id IS NOT NULL)), UNIQUE(id,request_id)
      );
      
      CREATE UNIQUE INDEX uq_active_intake_appointment ON appointments(intake_id) WHERE status='booked';
      
      CREATE UNIQUE INDEX uq_active_request_appointment ON appointments(request_id) WHERE status='booked';
      
      CREATE TABLE reservations (
       id TEXT PRIMARY KEY NOT NULL, request_item_id TEXT NOT NULL, request_id TEXT NOT NULL, equipment_id TEXT NOT NULL, recipient_id TEXT NOT NULL,
       status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','fulfilled','cancelled','expired')),
       reserved_by TEXT NOT NULL REFERENCES users(id), closed_by TEXT REFERENCES users(id), reserved_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, expires_at TIMESTAMPTZ,
       FOREIGN KEY(request_item_id,request_id,equipment_id) REFERENCES request_items(id,request_id,equipment_id), FOREIGN KEY(request_id,recipient_id) REFERENCES equipment_requests(id,recipient_id),
       UNIQUE(id,equipment_id,recipient_id,request_id)
      );
      
      CREATE UNIQUE INDEX uq_active_equipment_reservation ON reservations(equipment_id) WHERE status='active';
      
      CREATE TABLE legal_document_versions (
       id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('recipient_waiver','donor_certification')),
       version TEXT NOT NULL, title TEXT NOT NULL, exact_text TEXT NOT NULL, text_sha256 TEXT NOT NULL CHECK(length(text_sha256)=64),
       published_at TIMESTAMPTZ NOT NULL, published_by TEXT NOT NULL REFERENCES users(id), UNIQUE(kind,version)
      );
      
      CREATE TABLE active_legal_documents (kind TEXT PRIMARY KEY NOT NULL CHECK(kind IN ('recipient_waiver','donor_certification')), version_id TEXT NOT NULL REFERENCES legal_document_versions(id));
      
      CREATE TABLE signed_waivers (
       id TEXT PRIMARY KEY NOT NULL, recipient_id TEXT NOT NULL REFERENCES recipients(id), request_id TEXT NOT NULL,
       version_id TEXT NOT NULL REFERENCES legal_document_versions(id), signer_name TEXT NOT NULL, signer_capacity TEXT NOT NULL CHECK(signer_capacity IN ('self','authorized_representative')),
       representative_authority TEXT, signature_method TEXT NOT NULL CHECK(signature_method IN ('typed','drawn','external_provider')), signature_evidence_file_id TEXT NOT NULL REFERENCES files(id),
       signed_pdf_file_id TEXT NOT NULL UNIQUE REFERENCES files(id), signed_at TIMESTAMPTZ NOT NULL, consent_text TEXT NOT NULL, metadata_json JSONB,
       FOREIGN KEY(request_id,recipient_id) REFERENCES equipment_requests(id,recipient_id), UNIQUE(id,recipient_id,request_id),
       CHECK(signer_capacity <> 'authorized_representative' OR (representative_authority IS NOT NULL AND length(trim(representative_authority))>0))
      );
      
      CREATE TABLE signed_donor_certifications (
       id TEXT PRIMARY KEY NOT NULL, intake_id TEXT NOT NULL REFERENCES intake_submissions(id), version_id TEXT NOT NULL REFERENCES legal_document_versions(id),
       signer_name TEXT NOT NULL, signature_evidence_file_id TEXT NOT NULL REFERENCES files(id), signed_pdf_file_id TEXT NOT NULL UNIQUE REFERENCES files(id), signed_at TIMESTAMPTZ NOT NULL, consent_text TEXT NOT NULL
      );
      
      CREATE TABLE distributions (
       id TEXT PRIMARY KEY NOT NULL, reservation_id TEXT NOT NULL UNIQUE, equipment_id TEXT NOT NULL UNIQUE, recipient_id TEXT NOT NULL, request_id TEXT NOT NULL,
       waiver_id TEXT NOT NULL, appointment_id TEXT NOT NULL, released_by TEXT NOT NULL REFERENCES users(id), released_at TIMESTAMPTZ NOT NULL,
       pickup_signature_file_id TEXT NOT NULL REFERENCES files(id), condition_at_pickup TEXT NOT NULL, notes TEXT,
       FOREIGN KEY(reservation_id,equipment_id,recipient_id,request_id) REFERENCES reservations(id,equipment_id,recipient_id,request_id),
       FOREIGN KEY(waiver_id,recipient_id,request_id) REFERENCES signed_waivers(id,recipient_id,request_id), FOREIGN KEY(appointment_id,request_id) REFERENCES appointments(id,request_id)
      );
      
      CREATE TABLE volunteer_shifts (
       id TEXT PRIMARY KEY NOT NULL, location_id TEXT NOT NULL REFERENCES locations(id), activity TEXT NOT NULL, starts_at TIMESTAMPTZ NOT NULL, ends_at TIMESTAMPTZ NOT NULL,
       capacity INTEGER NOT NULL CHECK(capacity>0), created_by TEXT NOT NULL REFERENCES users(id), cancelled_at TIMESTAMPTZ, notes TEXT, CHECK(ends_at>starts_at)
      );
      
      CREATE TABLE shift_signups (
       shift_id TEXT NOT NULL REFERENCES volunteer_shifts(id), volunteer_id TEXT NOT NULL REFERENCES volunteers(user_id),
       status TEXT NOT NULL DEFAULT 'signed_up' CHECK(status IN ('signed_up','cancelled','attended','no_show')), signed_up_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
       attendance_recorded_by TEXT REFERENCES users(id), attendance_recorded_at TIMESTAMPTZ, PRIMARY KEY(shift_id,volunteer_id)
      );
      
      CREATE TABLE content_pages (id TEXT PRIMARY KEY NOT NULL, slug TEXT NOT NULL UNIQUE, title TEXT NOT NULL, body_markdown TEXT NOT NULL, published_at TIMESTAMPTZ, updated_by TEXT NOT NULL REFERENCES users(id), updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP);
      
      CREATE TABLE organization_settings (key TEXT PRIMARY KEY NOT NULL, value_json JSONB NOT NULL, updated_by TEXT NOT NULL REFERENCES users(id), updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP);
      
      CREATE TABLE conversations (id TEXT PRIMARY KEY NOT NULL, subject TEXT NOT NULL, equipment_id TEXT REFERENCES equipment(id), visitor_name TEXT, visitor_email TEXT, status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open','closed')), assigned_to TEXT REFERENCES users(id), created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP);
      
      CREATE TABLE conversation_participants (conversation_id TEXT NOT NULL REFERENCES conversations(id), user_id TEXT NOT NULL REFERENCES users(id), last_read_at TIMESTAMPTZ, PRIMARY KEY(conversation_id,user_id));
      
      CREATE TABLE messages (id TEXT PRIMARY KEY NOT NULL, conversation_id TEXT NOT NULL REFERENCES conversations(id), sender_user_id TEXT REFERENCES users(id), sender_kind TEXT NOT NULL CHECK(sender_kind IN ('user','visitor','system')), body TEXT NOT NULL, sent_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, CHECK((sender_kind='user' AND sender_user_id IS NOT NULL) OR (sender_kind<>'user' AND sender_user_id IS NULL)));
      
      CREATE TABLE message_files (message_id TEXT NOT NULL REFERENCES messages(id), file_id TEXT NOT NULL REFERENCES files(id), PRIMARY KEY(message_id,file_id));
      
      CREATE TABLE notification_outbox (
       id TEXT PRIMARY KEY NOT NULL, deduplication_key TEXT NOT NULL UNIQUE, recipient_user_id TEXT REFERENCES users(id), channel TEXT NOT NULL CHECK(channel IN ('email','sms','in_app')),
       destination TEXT NOT NULL, template_key TEXT NOT NULL, payload_json JSONB NOT NULL,
       status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','processing','sent','failed','cancelled')), attempts INTEGER NOT NULL DEFAULT 0 CHECK(attempts>=0),
       available_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, locked_at TIMESTAMPTZ, sent_at TIMESTAMPTZ, last_error TEXT,
       created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
      );
      
      CREATE TABLE audit_events (
       id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, actor_user_id TEXT REFERENCES users(id), actor_kind TEXT NOT NULL CHECK(actor_kind IN ('user','system','visitor')),
       entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, action TEXT NOT NULL, before_json JSONB, after_json JSONB,
       correlation_id TEXT, occurred_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
       CHECK((actor_kind='user' AND actor_user_id IS NOT NULL) OR (actor_kind<>'user' AND actor_user_id IS NULL))
      );
      
      CREATE TABLE record_holds (id TEXT PRIMARY KEY NOT NULL, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, reason TEXT NOT NULL, placed_by TEXT NOT NULL REFERENCES users(id), placed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP, released_by TEXT REFERENCES users(id), released_at TIMESTAMPTZ);
      
      CREATE INDEX idx_equipment_status_location ON equipment(status_code,location_id) WHERE archived_at IS NULL;
      
      CREATE INDEX idx_equipment_type ON equipment(type_id);
      
      CREATE INDEX idx_equipment_intake ON equipment(intake_item_id);
      
      CREATE INDEX idx_intakes_donor_date ON intake_submissions(donor_id,created_at);
      
      CREATE INDEX idx_intakes_review ON intake_submissions(status,submitted_at);
      
      CREATE INDEX idx_intake_items_submission ON intake_items(intake_id);
      
      CREATE INDEX idx_requests_recipient_date ON equipment_requests(recipient_id,submitted_at);
      
      CREATE INDEX idx_requests_review ON equipment_requests(status,submitted_at);
      
      CREATE INDEX idx_processing_equipment_date ON processing_events(equipment_id,performed_at);
      
      CREATE INDEX idx_history_equipment_date ON equipment_status_history(equipment_id,changed_at);
      
      CREATE INDEX idx_appointments_slot_status ON appointments(slot_id,status);
      
      CREATE INDEX idx_slots_location_date ON appointment_slots(location_id,starts_at);
      
      CREATE INDEX idx_reservations_request ON reservations(request_id,status);
      
      CREATE INDEX idx_waivers_recipient_date ON signed_waivers(recipient_id,signed_at);
      
      CREATE INDEX idx_distributions_recipient_date ON distributions(recipient_id,released_at);
      
      CREATE INDEX idx_shifts_location_date ON volunteer_shifts(location_id,starts_at);
      
      CREATE INDEX idx_signup_volunteer ON shift_signups(volunteer_id,status);
      
      CREATE INDEX idx_messages_conversation_date ON messages(conversation_id,sent_at);
      
      CREATE INDEX idx_outbox_due ON notification_outbox(status,available_at);
      
      CREATE INDEX idx_audit_entity_date ON audit_events(entity_type,entity_id,occurred_at);
      
      INSERT INTO roles VALUES ('admin','Admin'),('board','Founder / Board'),('volunteer','Volunteer'),('public','Registered public user');
      
      INSERT INTO inventory_statuses VALUES
       ('received','Received',10, FALSE),('awaiting_inspection','Awaiting inspection',20, FALSE),('inspected','Inspection complete',30, FALSE),('awaiting_sanitization','Awaiting sanitization',40, FALSE),('sanitized','Sanitized',50, FALSE),('needs_repair','Awaiting repair / preparation',60, FALSE),('cataloged','Cataloged',70, FALSE),('available','Ready for distribution',80, FALSE),('reserved','Reserved',90, TRUE),('distributed','Distributed',100, TRUE),('disposal','Disposal',110, FALSE),('unavailable','Unavailable',120, FALSE);
      
      INSERT INTO inventory_transitions VALUES ('received','awaiting_inspection'),('received','disposal'),('awaiting_inspection','inspected'),('awaiting_inspection','needs_repair'),('awaiting_inspection','disposal'),('inspected','awaiting_sanitization'),('awaiting_sanitization','sanitized'),('sanitized','cataloged'),('sanitized','needs_repair'),('needs_repair','awaiting_inspection'),('needs_repair','disposal'),('cataloged','available'),('available','reserved'),('available','unavailable'),('reserved','available'),('reserved','distributed'),('unavailable','awaiting_inspection');
      
      INSERT INTO equipment_categories VALUES ('wheelchairs','Wheelchairs', TRUE),('walkers','Walkers and rollators', TRUE),('bath','Bathroom safety', TRUE),('walking_aids','Crutches and canes', TRUE),('other','Other mobility aids', TRUE);
      
      CREATE VIEW public_available_equipment AS
       SELECT e.id,e.inventory_number,e.name,c.name AS category,t.name AS equipment_type,e.manufacturer,e.model,e.description,e.color,e.condition,e.height_cm,e.length_cm,e.width_cm,e.weight_kg,e.max_user_weight_kg,e.public_notes,l.name AS pickup_location
       FROM equipment e JOIN equipment_types t ON t.id=e.type_id JOIN equipment_categories c ON c.id=t.category_id JOIN locations l ON l.id=e.location_id
       WHERE e.status_code='available' AND e.archived_at IS NULL;
      
      CREATE VIEW public_equipment_photo_metadata AS
       SELECT ef.equipment_id,ef.file_id,ef.sort_order
       FROM equipment_files ef JOIN files f ON f.id=ef.file_id JOIN public_available_equipment e ON e.id=ef.equipment_id
       WHERE ef.purpose='photo' AND ef.public_approved = TRUE AND f.scan_status='clean' AND f.deleted_at IS NULL;
      
      CREATE VIEW inventory_status_totals AS SELECT status_code,location_id,count(*) AS item_count FROM equipment WHERE archived_at IS NULL GROUP BY status_code,location_id;
      
      CREATE VIEW purchase_totals AS SELECT p.id,p.currency,coalesce(sum(pl.quantity::numeric*pl.unit_cost_minor),0) AS total_cost_minor FROM purchases p LEFT JOIN purchase_lines pl ON pl.purchase_id=p.id GROUP BY p.id,p.currency;
      
      INSERT INTO permissions VALUES ('inventory.read','Read internal equipment records');
      
      INSERT INTO permissions VALUES ('inventory.write','Create and update equipment');
      
      INSERT INTO permissions VALUES ('inventory.process','Record inspection and preparation');
      
      INSERT INTO permissions VALUES ('intake.review','Review donation submissions');
      
      INSERT INTO permissions VALUES ('donors.read','Read donor contact records');
      
      INSERT INTO permissions VALUES ('recipients.read','Read recipient contact records');
      
      INSERT INTO permissions VALUES ('waivers.read','Read signed waivers when assigned');
      
      INSERT INTO permissions VALUES ('distribution.manage','Reserve and release equipment');
      
      INSERT INTO permissions VALUES ('shifts.read','View volunteer shifts');
      
      INSERT INTO permissions VALUES ('shifts.signup','Manage own shift signup');
      
      INSERT INTO permissions VALUES ('shifts.manage','Manage shift schedules');
      
      INSERT INTO permissions VALUES ('messages.use','Access authorized conversations');
      
      INSERT INTO permissions VALUES ('reports.read','Read and export reports');
      
      INSERT INTO permissions VALUES ('users.manage','Manage accounts and roles');
      
      INSERT INTO permissions VALUES ('content.manage','Edit organization content');
      
      INSERT INTO permissions VALUES ('settings.manage','Manage operational settings');
      
      INSERT INTO permissions VALUES ('audit.read','Read audit history');
      
      INSERT INTO permissions VALUES ('records.archive','Archive and restore operational records');
      
      INSERT INTO role_permissions SELECT 'admin',id FROM permissions;
      
      INSERT INTO role_permissions VALUES ('volunteer','inventory.read');
      
      INSERT INTO role_permissions VALUES ('volunteer','inventory.process');
      
      INSERT INTO role_permissions VALUES ('volunteer','intake.review');
      
      INSERT INTO role_permissions VALUES ('volunteer','distribution.manage');
      
      INSERT INTO role_permissions VALUES ('volunteer','shifts.read');
      
      INSERT INTO role_permissions VALUES ('volunteer','shifts.signup');
      
      INSERT INTO role_permissions VALUES ('volunteer','messages.use');
      
      INSERT INTO role_permissions VALUES ('board','inventory.read');
      
      INSERT INTO role_permissions VALUES ('board','inventory.process');
      
      INSERT INTO role_permissions VALUES ('board','intake.review');
      
      INSERT INTO role_permissions VALUES ('board','distribution.manage');
      
      INSERT INTO role_permissions VALUES ('board','shifts.read');
      
      INSERT INTO role_permissions VALUES ('board','shifts.signup');
      
      INSERT INTO role_permissions VALUES ('board','messages.use');
      
      INSERT INTO role_permissions VALUES ('board','donors.read');
      
      INSERT INTO role_permissions VALUES ('board','recipients.read');
      
      INSERT INTO role_permissions VALUES ('board','reports.read');
      
      INSERT INTO role_permissions VALUES ('public','messages.use');
      
      INSERT INTO schema_versions(version) VALUES(1);
      
      CREATE UNIQUE INDEX uq_users_email_casefold ON users (lower(email));
      
      CREATE FUNCTION fn_equipment_initial_status() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NEW.status_code<>'received' THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'New equipment must begin as received';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER equipment_initial_status BEFORE INSERT ON equipment
      FOR EACH ROW EXECUTE FUNCTION fn_equipment_initial_status();
      
      CREATE FUNCTION fn_equipment_transition() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
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
      $fn$;
      CREATE TRIGGER equipment_transition BEFORE UPDATE OF status_code ON equipment
      FOR EACH ROW EXECUTE FUNCTION fn_equipment_transition();
      
      CREATE FUNCTION fn_equipment_history_insert() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      INSERT INTO equipment_status_history(equipment_id,to_status,actor_id) VALUES(NEW.id,NEW.status_code,NEW.created_by);
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER equipment_history_insert AFTER INSERT ON equipment
      FOR EACH ROW EXECUTE FUNCTION fn_equipment_history_insert();
      
      CREATE FUNCTION fn_equipment_history_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NEW.status_code<>OLD.status_code THEN
      INSERT INTO equipment_status_history(equipment_id,from_status,to_status,actor_id) VALUES(NEW.id,OLD.status_code,NEW.status_code,NEW.updated_by);
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER equipment_history_update AFTER UPDATE OF status_code ON equipment
      FOR EACH ROW EXECUTE FUNCTION fn_equipment_history_update();
      
      CREATE FUNCTION fn_reservation_validate() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NEW.status<>'active' OR NOT EXISTS(SELECT 1 FROM equipment WHERE id=NEW.equipment_id AND status_code='available' AND archived_at IS NULL) THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Equipment is not available';
      END IF;
       IF NOT EXISTS(SELECT 1 FROM equipment_requests WHERE id=NEW.request_id AND status='approved') THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Approved request required';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER reservation_validate BEFORE INSERT ON reservations
      FOR EACH ROW EXECUTE FUNCTION fn_reservation_validate();
      
      CREATE FUNCTION fn_reservation_activate() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      UPDATE equipment SET status_code='reserved',updated_by=NEW.reserved_by,updated_at=CURRENT_TIMESTAMP WHERE id=NEW.equipment_id;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER reservation_activate AFTER INSERT ON reservations
      FOR EACH ROW EXECUTE FUNCTION fn_reservation_activate();
      
      CREATE FUNCTION fn_reservation_identity() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NEW.id<>OLD.id OR NEW.request_item_id<>OLD.request_item_id OR NEW.request_id<>OLD.request_id OR NEW.equipment_id<>OLD.equipment_id OR NEW.recipient_id<>OLD.recipient_id OR NEW.reserved_by<>OLD.reserved_by THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Reservation identity is immutable';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER reservation_identity BEFORE UPDATE ON reservations
      FOR EACH ROW EXECUTE FUNCTION fn_reservation_identity();
      
      CREATE FUNCTION fn_reservation_finish() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
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
      $fn$;
      CREATE TRIGGER reservation_finish BEFORE UPDATE OF status ON reservations
      FOR EACH ROW EXECUTE FUNCTION fn_reservation_finish();
      
      CREATE FUNCTION fn_reservation_release() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF OLD.status='active' AND NEW.status IN ('cancelled','expired') THEN
      UPDATE equipment SET status_code='available',updated_by=NEW.closed_by,updated_at=CURRENT_TIMESTAMP WHERE id=NEW.equipment_id;
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER reservation_release AFTER UPDATE OF status ON reservations
      FOR EACH ROW EXECUTE FUNCTION fn_reservation_release();
      
      CREATE FUNCTION fn_reservation_no_delete() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Retain reservation history; cancel instead';
      RETURN OLD;
      END;
      $fn$;
      CREATE TRIGGER reservation_no_delete BEFORE DELETE ON reservations
      FOR EACH ROW EXECUTE FUNCTION fn_reservation_no_delete();
      
      CREATE FUNCTION fn_distribution_validate() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NOT EXISTS(SELECT 1 FROM reservations WHERE id=NEW.reservation_id AND status='active') THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Active reservation required';
      END IF;
       IF NOT EXISTS(SELECT 1 FROM appointments WHERE id=NEW.appointment_id AND status='booked') THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Booked pickup required';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER distribution_validate BEFORE INSERT ON distributions
      FOR EACH ROW EXECUTE FUNCTION fn_distribution_validate();
      
      CREATE FUNCTION fn_distribution_complete() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      UPDATE equipment SET status_code='distributed',updated_by=NEW.released_by,updated_at=NEW.released_at WHERE id=NEW.equipment_id;
       UPDATE reservations SET status='fulfilled',closed_by=NEW.released_by WHERE id=NEW.reservation_id;
       UPDATE equipment_requests SET status='completed' WHERE id=NEW.request_id AND NOT EXISTS(SELECT 1 FROM request_items ri WHERE ri.request_id=NEW.request_id AND NOT EXISTS(SELECT 1 FROM distributions d WHERE d.request_id=ri.request_id AND d.equipment_id=ri.equipment_id));
       UPDATE appointments SET status='completed' WHERE id=NEW.appointment_id AND EXISTS(SELECT 1 FROM equipment_requests WHERE id=NEW.request_id AND status='completed');
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER distribution_complete AFTER INSERT ON distributions
      FOR EACH ROW EXECUTE FUNCTION fn_distribution_complete();
      
      CREATE FUNCTION fn_waiver_document_kind() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NOT EXISTS(SELECT 1 FROM legal_document_versions WHERE id=NEW.version_id AND kind='recipient_waiver') THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Recipient waiver version required';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER waiver_document_kind BEFORE INSERT ON signed_waivers
      FOR EACH ROW EXECUTE FUNCTION fn_waiver_document_kind();
      
      CREATE FUNCTION fn_certification_document_kind() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NOT EXISTS(SELECT 1 FROM legal_document_versions WHERE id=NEW.version_id AND kind='donor_certification') THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Donor certification version required';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER certification_document_kind BEFORE INSERT ON signed_donor_certifications
      FOR EACH ROW EXECUTE FUNCTION fn_certification_document_kind();
      
      CREATE FUNCTION fn_active_document_kind_insert() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NOT EXISTS(SELECT 1 FROM legal_document_versions WHERE id=NEW.version_id AND kind=NEW.kind) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document kind mismatch';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER active_document_kind_insert BEFORE INSERT ON active_legal_documents
      FOR EACH ROW EXECUTE FUNCTION fn_active_document_kind_insert();
      
      CREATE FUNCTION fn_active_document_kind_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NOT EXISTS(SELECT 1 FROM legal_document_versions WHERE id=NEW.version_id AND kind=NEW.kind) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Document kind mismatch';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER active_document_kind_update BEFORE UPDATE ON active_legal_documents
      FOR EACH ROW EXECUTE FUNCTION fn_active_document_kind_update();
      
      CREATE FUNCTION fn_legal_document_versions_no_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER legal_document_versions_no_update BEFORE UPDATE ON legal_document_versions
      FOR EACH ROW EXECUTE FUNCTION fn_legal_document_versions_no_update();
      
      CREATE FUNCTION fn_legal_document_versions_no_delete() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN OLD;
      END;
      $fn$;
      CREATE TRIGGER legal_document_versions_no_delete BEFORE DELETE ON legal_document_versions
      FOR EACH ROW EXECUTE FUNCTION fn_legal_document_versions_no_delete();
      
      CREATE FUNCTION fn_signed_waivers_no_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER signed_waivers_no_update BEFORE UPDATE ON signed_waivers
      FOR EACH ROW EXECUTE FUNCTION fn_signed_waivers_no_update();
      
      CREATE FUNCTION fn_signed_waivers_no_delete() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN OLD;
      END;
      $fn$;
      CREATE TRIGGER signed_waivers_no_delete BEFORE DELETE ON signed_waivers
      FOR EACH ROW EXECUTE FUNCTION fn_signed_waivers_no_delete();
      
      CREATE FUNCTION fn_signed_donor_certifications_no_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER signed_donor_certifications_no_update BEFORE UPDATE ON signed_donor_certifications
      FOR EACH ROW EXECUTE FUNCTION fn_signed_donor_certifications_no_update();
      
      CREATE FUNCTION fn_signed_donor_certifications_no_delete() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN OLD;
      END;
      $fn$;
      CREATE TRIGGER signed_donor_certifications_no_delete BEFORE DELETE ON signed_donor_certifications
      FOR EACH ROW EXECUTE FUNCTION fn_signed_donor_certifications_no_delete();
      
      CREATE FUNCTION fn_distributions_no_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER distributions_no_update BEFORE UPDATE ON distributions
      FOR EACH ROW EXECUTE FUNCTION fn_distributions_no_update();
      
      CREATE FUNCTION fn_distributions_no_delete() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN OLD;
      END;
      $fn$;
      CREATE TRIGGER distributions_no_delete BEFORE DELETE ON distributions
      FOR EACH ROW EXECUTE FUNCTION fn_distributions_no_delete();
      
      CREATE FUNCTION fn_equipment_status_history_no_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER equipment_status_history_no_update BEFORE UPDATE ON equipment_status_history
      FOR EACH ROW EXECUTE FUNCTION fn_equipment_status_history_no_update();
      
      CREATE FUNCTION fn_equipment_status_history_no_delete() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN OLD;
      END;
      $fn$;
      CREATE TRIGGER equipment_status_history_no_delete BEFORE DELETE ON equipment_status_history
      FOR EACH ROW EXECUTE FUNCTION fn_equipment_status_history_no_delete();
      
      CREATE FUNCTION fn_processing_events_no_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER processing_events_no_update BEFORE UPDATE ON processing_events
      FOR EACH ROW EXECUTE FUNCTION fn_processing_events_no_update();
      
      CREATE FUNCTION fn_processing_events_no_delete() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN OLD;
      END;
      $fn$;
      CREATE TRIGGER processing_events_no_delete BEFORE DELETE ON processing_events
      FOR EACH ROW EXECUTE FUNCTION fn_processing_events_no_delete();
      
      CREATE FUNCTION fn_audit_events_no_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER audit_events_no_update BEFORE UPDATE ON audit_events
      FOR EACH ROW EXECUTE FUNCTION fn_audit_events_no_update();
      
      CREATE FUNCTION fn_audit_events_no_delete() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Historical evidence is immutable';
      RETURN OLD;
      END;
      $fn$;
      CREATE TRIGGER audit_events_no_delete BEFORE DELETE ON audit_events
      FOR EACH ROW EXECUTE FUNCTION fn_audit_events_no_delete();
      
      CREATE FUNCTION fn_files_signed_no_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF EXISTS(SELECT 1 FROM signed_waivers WHERE signature_evidence_file_id=OLD.id OR signed_pdf_file_id=OLD.id) OR EXISTS(SELECT 1 FROM signed_donor_certifications WHERE signature_evidence_file_id=OLD.id OR signed_pdf_file_id=OLD.id) OR EXISTS(SELECT 1 FROM distributions WHERE pickup_signature_file_id=OLD.id) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Signed file metadata is immutable';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER files_signed_no_update BEFORE UPDATE ON files
      FOR EACH ROW EXECUTE FUNCTION fn_files_signed_no_update();
      
      CREATE FUNCTION fn_files_signed_no_delete() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF EXISTS(SELECT 1 FROM signed_waivers WHERE signature_evidence_file_id=OLD.id OR signed_pdf_file_id=OLD.id) OR EXISTS(SELECT 1 FROM signed_donor_certifications WHERE signature_evidence_file_id=OLD.id OR signed_pdf_file_id=OLD.id) OR EXISTS(SELECT 1 FROM distributions WHERE pickup_signature_file_id=OLD.id) THEN
      RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Signed file metadata is immutable';
      END IF;
      RETURN OLD;
      END;
      $fn$;
      CREATE TRIGGER files_signed_no_delete BEFORE DELETE ON files
      FOR EACH ROW EXECUTE FUNCTION fn_files_signed_no_delete();
      
      CREATE FUNCTION fn_signed_waivers_clean_files() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NOT EXISTS(SELECT 1 FROM files WHERE id=NEW.signature_evidence_file_id AND scan_status='clean' AND deleted_at IS NULL) THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean stored evidence required';
      END IF;
      IF NOT EXISTS(SELECT 1 FROM files WHERE id=NEW.signed_pdf_file_id AND scan_status='clean' AND deleted_at IS NULL AND mime_type='application/pdf') THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean stored evidence required';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER signed_waivers_clean_files BEFORE INSERT ON signed_waivers
      FOR EACH ROW EXECUTE FUNCTION fn_signed_waivers_clean_files();
      
      CREATE FUNCTION fn_signed_donor_certifications_clean_files() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NOT EXISTS(SELECT 1 FROM files WHERE id=NEW.signature_evidence_file_id AND scan_status='clean' AND deleted_at IS NULL) THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean stored evidence required';
      END IF;
      IF NOT EXISTS(SELECT 1 FROM files WHERE id=NEW.signed_pdf_file_id AND scan_status='clean' AND deleted_at IS NULL AND mime_type='application/pdf') THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean stored evidence required';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER signed_donor_certifications_clean_files BEFORE INSERT ON signed_donor_certifications
      FOR EACH ROW EXECUTE FUNCTION fn_signed_donor_certifications_clean_files();
      
      CREATE FUNCTION fn_distributions_clean_files() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NOT EXISTS(SELECT 1 FROM files WHERE id=NEW.pickup_signature_file_id AND scan_status='clean' AND deleted_at IS NULL) THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Clean stored evidence required';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER distributions_clean_files BEFORE INSERT ON distributions
      FOR EACH ROW EXECUTE FUNCTION fn_distributions_clean_files();
      
      CREATE FUNCTION fn_appointment_validate_insert() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
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
      $fn$;
      CREATE TRIGGER appointment_validate_insert BEFORE INSERT ON appointments
      FOR EACH ROW EXECUTE FUNCTION fn_appointment_validate_insert();
      
      CREATE FUNCTION fn_signup_validate_insert() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
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
      $fn$;
      CREATE TRIGGER signup_validate_insert BEFORE INSERT ON shift_signups
      FOR EACH ROW EXECUTE FUNCTION fn_signup_validate_insert();
      
      CREATE FUNCTION fn_appointment_validate_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
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
      $fn$;
      CREATE TRIGGER appointment_validate_update BEFORE UPDATE ON appointments
      FOR EACH ROW EXECUTE FUNCTION fn_appointment_validate_update();
      
      CREATE FUNCTION fn_signup_validate_update() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
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
      $fn$;
      CREATE TRIGGER signup_validate_update BEFORE UPDATE ON shift_signups
      FOR EACH ROW EXECUTE FUNCTION fn_signup_validate_update();
      
      CREATE FUNCTION fn_slot_preserve_bookings() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
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
      $fn$;
      CREATE TRIGGER slot_preserve_bookings BEFORE UPDATE ON appointment_slots
      FOR EACH ROW EXECUTE FUNCTION fn_slot_preserve_bookings();
      
      CREATE FUNCTION fn_shift_preserve_signups() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF NEW.capacity<(SELECT count(*) FROM shift_signups WHERE shift_id=OLD.id AND status IN ('signed_up','attended')) THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Capacity below existing signups';
      END IF;
       IF EXISTS(SELECT 1 FROM shift_signups WHERE shift_id=OLD.id AND status='signed_up') AND (NEW.starts_at<>OLD.starts_at OR NEW.ends_at<>OLD.ends_at OR NEW.location_id<>OLD.location_id) THEN
       RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'Resolve signups before rescheduling shift';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER shift_preserve_signups BEFORE UPDATE ON volunteer_shifts
      FOR EACH ROW EXECUTE FUNCTION fn_shift_preserve_signups();
      
      CREATE FUNCTION fn_shift_cancel_signups() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
      IF OLD.cancelled_at IS NULL AND NEW.cancelled_at IS NOT NULL THEN
      UPDATE shift_signups SET status='cancelled' WHERE shift_id=NEW.id AND status='signed_up';
      END IF;
      RETURN NEW;
      END;
      $fn$;
      CREATE TRIGGER shift_cancel_signups AFTER UPDATE OF cancelled_at ON volunteer_shifts
      FOR EACH ROW EXECUTE FUNCTION fn_shift_cancel_signups();
      
      
      -- SQLite's single-writer behavior cannot simply be assumed in PostgreSQL.
      -- Enforce SERIALIZABLE for every business write so SSI can reject write skew
      -- in capacity, overlap and multi-table lifecycle checks. Retry whole transactions.
      CREATE FUNCTION require_serializable_write() RETURNS trigger
      LANGUAGE plpgsql SET search_path = mobility_exchange, pg_catalog AS $fn$
      BEGIN
       IF current_setting('transaction_isolation') <> 'serializable' THEN
        RAISE EXCEPTION USING ERRCODE='25001', MESSAGE='Use BEGIN ISOLATION LEVEL SERIALIZABLE for Mobility Exchange writes';
       END IF;
       RETURN NULL;
      END;
      $fn$;
      
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON schema_versions FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON users FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON roles FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON permissions FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON role_permissions FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON user_roles FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON user_permission_grants FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON locations FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON location_hours FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON location_closures FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON donors FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON recipients FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON volunteers FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON equipment_categories FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON equipment_types FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON inventory_statuses FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON inventory_transitions FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON files FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON intake_submissions FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON intake_items FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON intake_item_files FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON purchases FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON purchase_lines FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON equipment FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON equipment_files FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON processing_events FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON equipment_status_history FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON appointment_slots FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON equipment_requests FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON request_items FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON appointments FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON reservations FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON legal_document_versions FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON active_legal_documents FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON signed_waivers FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON signed_donor_certifications FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON distributions FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON volunteer_shifts FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON shift_signups FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON content_pages FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON organization_settings FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON conversations FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON conversation_participants FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON messages FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON message_files FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON notification_outbox FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON audit_events FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE TRIGGER require_serializable BEFORE INSERT OR UPDATE OR DELETE ON record_holds FOR EACH STATEMENT EXECUTE FUNCTION require_serializable_write();
      
      CREATE FUNCTION reject_truncate() RETURNS trigger
      LANGUAGE plpgsql AS $fn$
      BEGIN
       RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='TRUNCATE is not a supported application operation';
      END;
      $fn$;
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON schema_versions FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON users FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON roles FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON permissions FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON role_permissions FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON user_roles FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON user_permission_grants FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON locations FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON location_hours FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON location_closures FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON donors FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON recipients FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON volunteers FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON equipment_categories FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON equipment_types FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON inventory_statuses FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON inventory_transitions FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON files FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON intake_submissions FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON intake_items FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON intake_item_files FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON purchases FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON purchase_lines FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON equipment FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON equipment_files FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON processing_events FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON equipment_status_history FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON appointment_slots FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON equipment_requests FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON request_items FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON appointments FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON reservations FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON legal_document_versions FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON active_legal_documents FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON signed_waivers FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON signed_donor_certifications FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON distributions FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON volunteer_shifts FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON shift_signups FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON content_pages FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON organization_settings FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON conversations FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON conversation_participants FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON messages FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON message_files FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON notification_outbox FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON audit_events FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      CREATE TRIGGER no_truncate BEFORE TRUNCATE ON record_holds FOR EACH STATEMENT EXECUTE FUNCTION reject_truncate();
      
      -- Provision explicit application grants separately. No PUBLIC access is granted.
      REVOKE ALL ON SCHEMA mobility_exchange FROM PUBLIC;
      REVOKE ALL ON ALL TABLES IN SCHEMA mobility_exchange FROM PUBLIC;
      REVOKE ALL ON ALL SEQUENCES IN SCHEMA mobility_exchange FROM PUBLIC;
      REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA mobility_exchange FROM PUBLIC;
    SQL
    # Rails records the migration version before committing this transaction.
    # Restore its search path so public.schema_migrations remains visible.
    execute "SELECT set_config('search_path', #{connection.quote(original_search_path)}, true)"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "This schema preserves signed documents and audit history. Restore a reviewed backup or write an explicit removal migration."
  end
end
