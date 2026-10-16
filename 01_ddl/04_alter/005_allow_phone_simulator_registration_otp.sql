ALTER TABLE identity.user_verification_codes
  DROP CONSTRAINT ck_user_verification_codes_channel,
  DROP CONSTRAINT ck_user_verification_codes_context_purpose_channel,
  ALTER COLUMN channel TYPE VARCHAR(20),
  ADD CONSTRAINT ck_user_verification_codes_channel
    CHECK (channel IN ('EMAIL', 'SMS', 'PHONE_SIMULATOR')),
  ADD CONSTRAINT ck_user_verification_codes_context_purpose_channel
    CHECK (
      (
        registration_request_id IS NOT NULL
        AND (
          (purpose = 'EMAIL_VERIFICATION' AND channel = 'EMAIL')
          OR (purpose = 'PHONE_VERIFICATION' AND channel IN ('SMS', 'PHONE_SIMULATOR'))
        )
      )
      OR (
        user_id IS NOT NULL
        AND (
          (purpose = 'PASSWORD_RESET' AND channel = 'EMAIL')
          OR purpose = 'PROFILE_CONTACT_CHANGE'
        )
      )
    );
