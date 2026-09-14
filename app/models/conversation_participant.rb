class ConversationParticipant < MobilityRecord
  self.table_name = "mobility_exchange.conversation_participants"
  self.primary_key = ["conversation_id", "user_id"]
end
