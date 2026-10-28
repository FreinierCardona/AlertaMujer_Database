-- Limita a una sola cuenta con rol ENTITY_ADMIN, sin depender de su estado de habilitación.
CREATE UNIQUE INDEX ux_users_single_entity_admin
  ON identity.users (role)
  WHERE role = 'ENTITY_ADMIN';
