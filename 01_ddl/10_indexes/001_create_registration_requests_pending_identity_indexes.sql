-- Reserva el nombre de usuario mientras la solicitud permanezca pendiente.
CREATE UNIQUE INDEX ux_registration_requests_pending_username
  ON identity.registration_requests (username)
  WHERE status = 'PENDING';

-- Reserva el correo solo durante el registro pendiente.
CREATE UNIQUE INDEX ux_registration_requests_pending_email
  ON identity.registration_requests (email)
  WHERE status = 'PENDING';

-- Impide solicitudes pendientes simultáneas para el mismo teléfono.
CREATE UNIQUE INDEX ux_registration_requests_pending_phone
  ON identity.registration_requests (phone)
  WHERE status = 'PENDING';
