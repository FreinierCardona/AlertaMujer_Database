CREATE UNIQUE INDEX ux_registration_requests_pending_username
  ON identity.registration_requests (username)
  WHERE status = 'PENDING';

CREATE UNIQUE INDEX ux_registration_requests_pending_email
  ON identity.registration_requests (email)
  WHERE status = 'PENDING';

CREATE UNIQUE INDEX ux_registration_requests_pending_phone
  ON identity.registration_requests (phone)
  WHERE status = 'PENDING';
