CREATE TABLE identity.user_credentials (
  credential_id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID         NOT NULL UNIQUE,
  password_hash       VARCHAR(255) NOT NULL,
  password_updated_at TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT fk_user_credentials_user
    FOREIGN KEY (user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_user_credentials_password_hash_not_blank
    CHECK (btrim(password_hash) <> ''),

  CONSTRAINT ck_user_credentials_updated_after_created
    CHECK (updated_at >= created_at)
);
