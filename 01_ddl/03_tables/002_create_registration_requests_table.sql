CREATE TABLE identity.registration_requests (
  registration_request_id UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  username                CITEXT       NOT NULL,
  first_names             VARCHAR(100) NOT NULL,
  last_names              VARCHAR(100) NOT NULL,
  email                   CITEXT       NOT NULL,
  phone                   VARCHAR(20)  NOT NULL,
  password_hash           VARCHAR(255) NOT NULL,
  status                  VARCHAR(10)  NOT NULL DEFAULT 'PENDING',
  expires_at              TIMESTAMPTZ  NOT NULL,
  created_at              TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT ck_registration_requests_username_not_blank
    CHECK (btrim(username::TEXT) <> ''),

  CONSTRAINT ck_registration_requests_first_names_not_blank
    CHECK (btrim(first_names) <> ''),

  CONSTRAINT ck_registration_requests_last_names_not_blank
    CHECK (btrim(last_names) <> ''),

  CONSTRAINT ck_registration_requests_email_not_blank
    CHECK (btrim(email::TEXT) <> ''),

  CONSTRAINT ck_registration_requests_phone_format
    CHECK (phone ~ '^3[0-9]{9}$'),

  CONSTRAINT ck_registration_requests_password_hash_not_blank
    CHECK (btrim(password_hash) <> ''),

  CONSTRAINT ck_registration_requests_status
    CHECK (status IN ('PENDING', 'COMPLETED', 'CANCELLED', 'EXPIRED')),

  CONSTRAINT ck_registration_requests_expires_after_created
    CHECK (expires_at > created_at),

  CONSTRAINT ck_registration_requests_updated_after_created
    CHECK (updated_at >= created_at)
);
