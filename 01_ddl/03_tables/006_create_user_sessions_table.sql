CREATE TABLE identity.user_sessions (
  session_id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID        NOT NULL,
  refresh_token_hash  VARCHAR(255) NOT NULL,
  client_type         VARCHAR(9)  NOT NULL,
  device_label        TEXT,
  last_used_at        TIMESTAMPTZ NOT NULL,
  expires_at          TIMESTAMPTZ NOT NULL,
  revoked_at          TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT fk_user_sessions_user
    FOREIGN KEY (user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT uq_user_sessions_refresh_token_hash
    UNIQUE (refresh_token_hash),

  CONSTRAINT ck_user_sessions_refresh_token_hash_not_blank
    CHECK (btrim(refresh_token_hash) <> ''),

  CONSTRAINT ck_user_sessions_client_type
    CHECK (client_type IN ('MOBILE', 'ADMIN_WEB')),

  CONSTRAINT ck_user_sessions_last_used_after_created
    CHECK (last_used_at >= created_at),

  CONSTRAINT ck_user_sessions_expires_after_last_used
    CHECK (expires_at > last_used_at),

  CONSTRAINT ck_user_sessions_revoked_after_last_used
    CHECK (revoked_at IS NULL OR revoked_at >= last_used_at)
);
