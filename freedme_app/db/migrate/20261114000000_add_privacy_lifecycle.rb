# FR021/FR022, NFR004, DEC03; explicit retention decisions of 14 November 2026.
class AddPrivacyLifecycle < ActiveRecord::Migration[8.1]
  def change
    create_table 'freedme.privacy_deletion_requests', id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.uuid :account_id, null: false
      t.string :state, null: false, default: 'pending_review'
      t.datetime :requested_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_foreign_key 'freedme.privacy_deletion_requests', 'freedme.accounts', column: :account_id
    add_index 'freedme.privacy_deletion_requests', :account_id, unique: true
    add_check_constraint 'freedme.privacy_deletion_requests', "state IN ('pending_review', 'reviewing')", name: 'privacy_request_state'
    create_table 'freedme.reporting_archives', id: :uuid, default: -> { 'gen_random_uuid()' } do |t|
      t.uuid :exchange_id
      t.uuid :listing_id, null: false
      t.string :category_code, null: false
      t.string :offer_kind, null: false
      t.string :outcome, null: false
      t.datetime :archived_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
    end
    add_foreign_key 'freedme.reporting_archives', 'freedme.exchanges', column: :exchange_id
    add_foreign_key 'freedme.reporting_archives', 'freedme.listings', column: :listing_id
    add_index 'freedme.reporting_archives', :exchange_id, unique: true
    add_index 'freedme.reporting_archives', :listing_id, unique: true, where: 'exchange_id IS NULL', name: 'archive_withdrawn_listing'
    reversible do |direction|
      direction.up { execute transfer_guard(true) }
      direction.down { execute transfer_guard(false) }
    end
    add_column 'freedme.accounts', :last_activity_at, :datetime
    add_column 'freedme.accounts', :last_inactivity_reviewed_at, :datetime
    add_column 'freedme.exchanges', :retention_ended_at, :datetime
    add_column 'freedme.exchanges', :retention_end_reason, :string
    add_column 'freedme.equipment_questions', :archived_at, :datetime
    add_index 'freedme.accounts', :last_activity_at
    add_index 'freedme.exchanges', :retention_ended_at
    add_check_constraint 'freedme.exchanges', "(retention_ended_at IS NULL) = (retention_end_reason IS NULL)", name: 'retention_end_complete'
    add_check_constraint 'freedme.exchanges', "retention_end_reason IN ('gift_confirmed', 'gift_pickup_elapsed', 'loan_return_confirmed')", name: 'retention_end_reason_valid'
  end
  private
  def transfer_guard(either_participant)
    return_condition = either_participant ? "NEW.actor_id IS NULL OR NEW.actor_id NOT IN(ex.donor_id,ex.requester_id)" : "NEW.actor_id IS DISTINCT FROM ex.donor_id"
    <<~SQL
      CREATE OR REPLACE FUNCTION freedme.guard_transfer_event() RETURNS trigger
      LANGUAGE plpgsql SET search_path TO 'freedme', 'pg_catalog' AS $$
      DECLARE ex exchanges;
      BEGIN
       SELECT * INTO ex FROM exchanges WHERE id=NEW.exchange_id FOR UPDATE;
       IF NEW.event_type='handoff_confirmed' THEN
        IF NEW.actor_id IS NULL OR NEW.actor_id NOT IN(ex.donor_id,ex.requester_id) OR ex.state NOT IN('reserved','loaned','completed')
        THEN RAISE EXCEPTION 'Only a participant may confirm a reserved handoff'; END IF;
       ELSIF NEW.event_type='return_confirmed' THEN
        IF (#{return_condition}) OR ex.state NOT IN('loaned','completed')
        THEN RAISE EXCEPTION 'Only an authorized participant may confirm loan return'; END IF;
       END IF;
       RETURN NEW;
      END $$;
    SQL
  end
end
