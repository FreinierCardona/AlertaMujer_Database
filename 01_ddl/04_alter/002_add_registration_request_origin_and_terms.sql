ALTER TABLE identity.registration_requests
  ADD COLUMN account_origin    VARCHAR(20),
  ADD COLUMN accepted_terms_at TIMESTAMPTZ;

UPDATE identity.registration_requests
   SET account_origin = 'SELF_REGISTERED',
       accepted_terms_at = created_at
 WHERE account_origin IS NULL;

ALTER TABLE identity.registration_requests
  ALTER COLUMN account_origin SET NOT NULL,

  ADD CONSTRAINT ck_registration_requests_account_origin
    CHECK (account_origin IN ('SELF_REGISTERED', 'ADMIN_CREATED')),

  ADD CONSTRAINT ck_registration_requests_origin_terms
    CHECK (
      (account_origin = 'SELF_REGISTERED' AND accepted_terms_at IS NOT NULL)
      OR (account_origin = 'ADMIN_CREATED' AND accepted_terms_at IS NULL)
    );
