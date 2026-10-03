CREATE TABLE identity.users (
  user_id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  username          CITEXT       NOT NULL UNIQUE,
  first_names       VARCHAR(100) NOT NULL,
  last_names        VARCHAR(100) NOT NULL,
  email             CITEXT       NOT NULL UNIQUE,
  phone             VARCHAR(20)  NOT NULL UNIQUE,
  role              VARCHAR(20)  NOT NULL,
  account_status    VARCHAR(10)  NOT NULL,
  account_origin    VARCHAR(20)  NOT NULL,
  accepted_terms_at TIMESTAMPTZ,
  last_login_at     TIMESTAMPTZ,
  last_activity_at  TIMESTAMPTZ,
  disabled_at       TIMESTAMPTZ,
  created_at        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at        TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_users_username_not_blank
    CHECK (btrim(username::TEXT) <> ''),

  CONSTRAINT ck_users_first_names_not_blank
    CHECK (btrim(first_names) <> ''),

  CONSTRAINT ck_users_last_names_not_blank
    CHECK (btrim(last_names) <> ''),

  CONSTRAINT ck_users_email_not_blank
    CHECK (btrim(email::TEXT) <> ''),

  CONSTRAINT ck_users_phone_format
    CHECK (phone ~ '^3[0-9]{9}$'),

  CONSTRAINT ck_users_role
    CHECK (role IN ('USER', 'ENTITY_ADMIN')),

  CONSTRAINT ck_users_account_status
    CHECK (account_status IN ('ENABLED', 'DISABLED')),

  CONSTRAINT ck_users_account_origin
    CHECK (account_origin IN ('SELF_REGISTERED', 'ADMIN_CREATED')),

  CONSTRAINT ck_users_self_registered_terms_accepted
    CHECK (account_origin <> 'SELF_REGISTERED' OR accepted_terms_at IS NOT NULL),

  CONSTRAINT ck_users_disabled_at_matches_account_status
    CHECK (
      (account_status = 'DISABLED' AND disabled_at IS NOT NULL)
      OR (account_status = 'ENABLED' AND disabled_at IS NULL)
    ),

  CONSTRAINT ck_users_updated_after_created
    CHECK (updated_at >= created_at)
);
