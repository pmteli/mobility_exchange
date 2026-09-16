# frozen_string_literal: true
# Load from db/seeds.rb after migration or SQL structure load:
# load Rails.root.join("db/seeds/mobility_exchange.rb")
# Inserts missing lookup rows without overwriting existing configuration.
MobilityTransaction.call do
  ActiveRecord::Base.connection.execute <<~'SQL'
    SET LOCAL search_path = mobility_exchange, pg_catalog;
    INSERT INTO roles VALUES ('admin','Admin'),('board','Founder / Board'),('volunteer','Volunteer'),('public','Registered public user') ON CONFLICT DO NOTHING;
    INSERT INTO inventory_statuses VALUES
     ('received','Received',10, FALSE),('awaiting_inspection','Awaiting inspection',20, FALSE),('inspected','Inspection complete',30, FALSE),('awaiting_sanitization','Awaiting sanitization',40, FALSE),('sanitized','Sanitized',50, FALSE),('needs_repair','Awaiting repair / preparation',60, FALSE),('cataloged','Cataloged',70, FALSE),('available','Ready for distribution',80, FALSE),('reserved','Reserved',90, TRUE),('distributed','Distributed',100, TRUE),('disposal','Disposal',110, FALSE),('unavailable','Unavailable',120, FALSE) ON CONFLICT DO NOTHING;
    INSERT INTO inventory_transitions VALUES ('received','awaiting_inspection'),('received','disposal'),('awaiting_inspection','inspected'),('awaiting_inspection','needs_repair'),('awaiting_inspection','disposal'),('inspected','awaiting_sanitization'),('awaiting_sanitization','sanitized'),('sanitized','cataloged'),('sanitized','needs_repair'),('needs_repair','awaiting_inspection'),('needs_repair','disposal'),('cataloged','available'),('available','reserved'),('available','unavailable'),('reserved','available'),('reserved','distributed'),('unavailable','awaiting_inspection') ON CONFLICT DO NOTHING;
    INSERT INTO equipment_categories VALUES ('wheelchairs','Wheelchairs', TRUE),('walkers','Walkers and rollators', TRUE),('bath','Bathroom safety', TRUE),('walking_aids','Crutches and canes', TRUE),('other','Other mobility aids', TRUE) ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('inventory.read','Read internal equipment records') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('inventory.write','Create and update equipment') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('inventory.process','Record inspection and preparation') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('intake.review','Review donation submissions') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('donors.read','Read donor contact records') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('recipients.read','Read recipient contact records') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('waivers.read','Read signed waivers when assigned') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('distribution.manage','Reserve and release equipment') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('shifts.read','View volunteer shifts') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('shifts.signup','Manage own shift signup') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('shifts.manage','Manage shift schedules') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('messages.use','Access authorized conversations') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('reports.read','Read and export reports') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('users.manage','Manage accounts and roles') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('content.manage','Edit organization content') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('settings.manage','Manage operational settings') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('audit.read','Read audit history') ON CONFLICT DO NOTHING;
    INSERT INTO permissions VALUES ('records.archive','Archive and restore operational records') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions SELECT 'admin',id FROM permissions WHERE TRUE ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('volunteer','inventory.read') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('volunteer','inventory.process') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('volunteer','intake.review') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('volunteer','distribution.manage') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('volunteer','shifts.read') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('volunteer','shifts.signup') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('volunteer','messages.use') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('board','inventory.read') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('board','inventory.process') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('board','intake.review') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('board','distribution.manage') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('board','shifts.read') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('board','shifts.signup') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('board','messages.use') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('board','donors.read') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('board','recipients.read') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('board','reports.read') ON CONFLICT DO NOTHING;
    INSERT INTO role_permissions VALUES ('public','messages.use') ON CONFLICT DO NOTHING;
    INSERT INTO schema_versions(version) VALUES(1) ON CONFLICT DO NOTHING;
    -- structure.sql intentionally omits ACLs; restore the schema's baseline grants.
    REVOKE ALL ON SCHEMA mobility_exchange FROM PUBLIC;
    REVOKE ALL ON ALL TABLES IN SCHEMA mobility_exchange FROM PUBLIC;
    REVOKE ALL ON ALL SEQUENCES IN SCHEMA mobility_exchange FROM PUBLIC;
    REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA mobility_exchange FROM PUBLIC;
  SQL
end
