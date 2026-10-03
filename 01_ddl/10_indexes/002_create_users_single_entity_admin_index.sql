CREATE UNIQUE INDEX ux_users_single_entity_admin
  ON identity.users (role)
  WHERE role = 'ENTITY_ADMIN';
