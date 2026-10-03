CREATE INDEX ix_audit_logs_entity_created_at
  ON audit.audit_logs (entity_type, entity_id, created_at DESC);
