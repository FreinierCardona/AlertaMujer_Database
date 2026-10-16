DO $$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM identity.registration_requests
     WHERE flow_version = 'V2'
  ) THEN
    RAISE EXCEPTION 'HU-DB-028 rollback requires v2 registration requests to be purged or cancelled and removed first.';
  END IF;
END
$$;

ALTER TABLE identity.registration_requests
  DROP CONSTRAINT ck_registration_requests_origin_terms,
  DROP CONSTRAINT ck_registration_requests_registration_data_by_stage,
  DROP CONSTRAINT ck_registration_requests_v2_flow_secret,
  DROP CONSTRAINT ck_registration_requests_status_stage,
  DROP CONSTRAINT ck_registration_requests_registration_stage,
  DROP CONSTRAINT ck_registration_requests_flow_version,
  ADD CONSTRAINT ck_registration_requests_email_not_blank
    CHECK (btrim(email::TEXT) <> ''),
  ADD CONSTRAINT ck_registration_requests_password_hash_not_blank
    CHECK (btrim(password_hash) <> ''),
  ADD CONSTRAINT ck_registration_requests_origin_terms
    CHECK (
      (account_origin = 'SELF_REGISTERED' AND accepted_terms_at IS NOT NULL)
      OR (account_origin = 'ADMIN_CREATED' AND accepted_terms_at IS NULL)
    ),
  ALTER COLUMN email SET NOT NULL,
  ALTER COLUMN password_hash SET NOT NULL,
  DROP COLUMN flow_secret_hash,
  DROP COLUMN registration_stage,
  DROP COLUMN flow_version;
