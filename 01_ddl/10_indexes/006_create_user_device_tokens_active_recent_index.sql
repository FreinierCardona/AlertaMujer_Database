CREATE INDEX ix_user_device_tokens_active_recent
  ON notification.user_device_tokens (user_id, last_seen_at DESC NULLS LAST)
  WHERE is_active;
