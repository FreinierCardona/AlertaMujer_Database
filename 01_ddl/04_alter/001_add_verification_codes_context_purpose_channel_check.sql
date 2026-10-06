ALTER TABLE identity.user_verification_codes
  ADD CONSTRAINT ck_user_verification_codes_context_purpose_channel
    CHECK (
      (
        registration_request_id IS NOT NULL
        AND (
          (purpose = 'EMAIL_VERIFICATION' AND channel = 'EMAIL')
          OR (purpose = 'PHONE_VERIFICATION' AND channel = 'SMS')
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
