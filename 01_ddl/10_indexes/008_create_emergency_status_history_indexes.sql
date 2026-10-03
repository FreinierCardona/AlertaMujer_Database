CREATE INDEX ix_emergency_status_history_emergency_occurred_sequence
  ON emergency.emergency_status_history (emergency_id, occurred_at DESC, sequence_no DESC);
