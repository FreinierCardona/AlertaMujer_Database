-- Ordena los extremos de la relación para impedir duplicados aunque se inviertan emisor y receptor.
CREATE UNIQUE INDEX ux_emergency_contacts_canonical_pair
  ON contacts.emergency_contacts (
    LEAST(owner_user_id, contact_user_id),
    GREATEST(owner_user_id, contact_user_id)
  );

-- Facilita consultar las invitaciones enviadas por un usuario.
CREATE INDEX ix_emergency_contacts_owner_user_id
  ON contacts.emergency_contacts (owner_user_id);

-- Facilita consultar las invitaciones recibidas por un usuario.
CREATE INDEX ix_emergency_contacts_contact_user_id
  ON contacts.emergency_contacts (contact_user_id);
