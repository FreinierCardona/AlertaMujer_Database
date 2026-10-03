CREATE INDEX ix_emergency_chat_messages_emergency_sent_at
  ON emergency.emergency_chat_messages (emergency_id, sent_at DESC, chat_message_id DESC);
