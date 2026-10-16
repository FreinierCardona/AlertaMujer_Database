ALTER TABLE identity.registration_requests
  ADD COLUMN flow_version VARCHAR(2) NOT NULL DEFAULT 'V1',
  ADD COLUMN registration_stage VARCHAR(20) NOT NULL DEFAULT 'EMAIL_PENDING',
  ADD COLUMN flow_secret_hash VARCHAR(255);

ALTER TABLE identity.registration_requests
  DROP CONSTRAINT ck_registration_requests_origin_terms,
  DROP CONSTRAINT ck_registration_requests_email_not_blank,
  DROP CONSTRAINT ck_registration_requests_password_hash_not_blank,
  ALTER COLUMN email DROP NOT NULL,
  ALTER COLUMN password_hash DROP NOT NULL,
  ADD CONSTRAINT ck_registration_requests_flow_version
    CHECK (flow_version IN ('V1', 'V2')),
  ADD CONSTRAINT ck_registration_requests_registration_stage
    CHECK (registration_stage IN (
      'PHONE_PENDING', 'PHONE_VERIFIED', 'EMAIL_PENDING',
      'COMPLETED', 'CANCELLED', 'EXPIRED'
    )),
  ADD CONSTRAINT ck_registration_requests_status_stage
    CHECK (
      (flow_version = 'V1' AND registration_stage = 'EMAIL_PENDING')
      OR (
        flow_version = 'V2'
        AND (
          (status = 'PENDING' AND registration_stage IN ('PHONE_PENDING', 'PHONE_VERIFIED', 'EMAIL_PENDING'))
          OR (status = 'COMPLETED' AND registration_stage = 'COMPLETED')
          OR (status = 'CANCELLED' AND registration_stage = 'CANCELLED')
          OR (status = 'EXPIRED' AND registration_stage = 'EXPIRED')
        )
      )
    ),
  ADD CONSTRAINT ck_registration_requests_v2_flow_secret
    CHECK (
      flow_version = 'V1'
      OR (flow_secret_hash IS NOT NULL AND btrim(flow_secret_hash) <> '')
    ),
  ADD CONSTRAINT ck_registration_requests_registration_data_by_stage
    CHECK (
      (
        flow_version = 'V1'
        AND email IS NOT NULL
        AND btrim(email::TEXT) <> ''
        AND password_hash IS NOT NULL
        AND btrim(password_hash) <> ''
      )
      OR (
        flow_version = 'V2'
        AND (
          (
            registration_stage IN ('PHONE_PENDING', 'PHONE_VERIFIED')
            AND email IS NULL
            AND password_hash IS NULL
            AND accepted_terms_at IS NULL
          )
          OR (
            registration_stage IN ('EMAIL_PENDING', 'COMPLETED')
            AND email IS NOT NULL
            AND btrim(email::TEXT) <> ''
            AND password_hash IS NOT NULL
            AND btrim(password_hash) <> ''
            AND accepted_terms_at IS NOT NULL
          )
          OR registration_stage IN ('CANCELLED', 'EXPIRED')
        )
      )
    ),
  ADD CONSTRAINT ck_registration_requests_origin_terms
    CHECK (
      (account_origin = 'ADMIN_CREATED' AND flow_version = 'V1' AND accepted_terms_at IS NULL)
      OR (
        account_origin = 'SELF_REGISTERED'
        AND (
          (flow_version = 'V1' AND accepted_terms_at IS NOT NULL)
          OR (
            flow_version = 'V2'
            AND (
              (registration_stage IN ('PHONE_PENDING', 'PHONE_VERIFIED') AND accepted_terms_at IS NULL)
              OR (registration_stage IN ('EMAIL_PENDING', 'COMPLETED') AND accepted_terms_at IS NOT NULL)
              OR registration_stage IN ('CANCELLED', 'EXPIRED')
            )
          )
        )
      )
    );
