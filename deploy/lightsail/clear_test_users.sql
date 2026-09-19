\set ON_ERROR_STOP on
-- Manual maintenance only: stop web/worker and take a verified backup first.
-- Never invoked by migrations, startup, or seeds.
BEGIN ISOLATION LEVEL SERIALIZABLE;
DO $$ BEGIN
  IF current_database() NOT IN ('mobility_exchange_test_site', 'mobility_user_cleanup_rehearsal') THEN
    RAISE EXCEPTION 'This cleanup is restricted to the Mobility Exchange test database';
  END IF;
END $$;
SET LOCAL session_replication_role = replica;
SET LOCAL search_path = mobility_exchange, public;
CREATE TEMP TABLE preserved_counts AS
SELECT table_name, (xpath('/row/n/text()', query_to_xml(format('SELECT count(*) AS n FROM mobility_exchange.%I', table_name), false,true,'')))[1]::text::bigint AS n
FROM information_schema.tables WHERE table_schema='mobility_exchange' AND table_type='BASE TABLE'
AND table_name IN ('active_legal_documents','appointment_slots','content_pages','equipment','equipment_categories','equipment_types','equipment_files','inventory_statuses','inventory_transitions','legal_document_versions','location_closures','location_hours','locations','organization_settings','permissions','role_permissions','roles','schema_versions','volunteer_shifts');
UPDATE appointment_slots SET created_by=NULL;
UPDATE content_pages SET updated_by=NULL;
UPDATE equipment SET created_by=NULL, updated_by=NULL, assigned_volunteer_id=NULL,
  acquisition_kind='legacy', intake_item_id=NULL, purchase_line_id=NULL;
UPDATE legal_document_versions SET published_by=NULL;
UPDATE organization_settings SET updated_by=NULL;
UPDATE volunteer_shifts SET created_by=NULL;
UPDATE equipment_files SET approved_by=NULL;
UPDATE files SET uploaded_by=NULL WHERE id IN (SELECT file_id FROM equipment_files);
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['appointments','audit_events','conversation_participants','conversations','credentials','distributions','donors','equipment_requests','equipment_status_history','intake_item_files','intake_items','intake_submissions','login_sessions','message_files','messages','money_donations','notification_outbox','processing_events','purchase_lines','purchases','recipients','record_holds','request_items','reservations','shift_signups','signed_donor_certifications','signed_waivers','user_permission_grants','user_roles','volunteers','users'] LOOP
    EXECUTE format('DELETE FROM mobility_exchange.%I', t);
  END LOOP;
END $$;
DELETE FROM files WHERE id NOT IN (SELECT file_id FROM equipment_files);
-- Validate every FK explicitly before committing (maintenance temporarily skips triggers).
DO $$ DECLARE fk record; joins text; nonnull text; invalid boolean; r record; actual bigint; BEGIN
  FOR fk IN SELECT * FROM pg_constraint WHERE contype='f' AND connamespace='mobility_exchange'::regnamespace LOOP
    SELECT string_agg(format('c.%I = p.%I', ca.attname, pa.attname), ' AND '),
           string_agg(format('c.%I IS NOT NULL', ca.attname), ' AND ')
    INTO joins, nonnull
    FROM unnest(fk.conkey, fk.confkey) AS k(c,p)
    JOIN pg_attribute ca ON ca.attrelid=fk.conrelid AND ca.attnum=k.c
    JOIN pg_attribute pa ON pa.attrelid=fk.confrelid AND pa.attnum=k.p;
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM %s c WHERE %s AND NOT EXISTS (SELECT 1 FROM %s p WHERE %s))', fk.conrelid::regclass, nonnull, fk.confrelid::regclass, joins) INTO invalid;
    IF invalid THEN RAISE EXCEPTION 'Orphan records for %', fk.conname; END IF;
  END LOOP;
  FOR r IN SELECT * FROM preserved_counts LOOP
    EXECUTE format('SELECT count(*) FROM mobility_exchange.%I', r.table_name) INTO actual;
    IF actual <> r.n THEN RAISE EXCEPTION 'Preserved count changed: %', r.table_name; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM users) THEN RAISE EXCEPTION 'Users remain'; END IF;
END $$;
SET LOCAL session_replication_role = origin;
SELECT * FROM preserved_counts ORDER BY table_name;
COMMIT;
