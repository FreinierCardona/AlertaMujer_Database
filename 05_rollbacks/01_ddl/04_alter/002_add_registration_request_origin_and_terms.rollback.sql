ALTER TABLE identity.registration_requests
  DROP CONSTRAINT IF EXISTS ck_registration_requests_origin_terms,
  DROP CONSTRAINT IF EXISTS ck_registration_requests_account_origin,
  DROP COLUMN IF EXISTS accepted_terms_at,
  DROP COLUMN IF EXISTS account_origin;
