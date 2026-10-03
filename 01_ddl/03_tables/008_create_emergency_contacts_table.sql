CREATE TABLE contacts.emergency_contacts (
  contact_id          UUID        NOT NULL DEFAULT gen_random_uuid(),
  owner_user_id       UUID        NOT NULL,
  contact_user_id     UUID        NOT NULL,
  relationship_status VARCHAR(8)  NOT NULL DEFAULT 'PENDING',
  expires_at          TIMESTAMPTZ,
  status_changed_at   TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT pk_emergency_contacts
    PRIMARY KEY (contact_id),

  CONSTRAINT fk_emergency_contacts_owner_user
    FOREIGN KEY (owner_user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT fk_emergency_contacts_contact_user
    FOREIGN KEY (contact_user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_emergency_contacts_distinct_users
    CHECK (owner_user_id <> contact_user_id),

  CONSTRAINT ck_emergency_contacts_relationship_status
    CHECK (relationship_status IN ('PENDING', 'ACCEPTED', 'EXPIRED', 'REJECTED')),

  CONSTRAINT ck_emergency_contacts_status_dates
    CHECK (
      (relationship_status = 'PENDING' AND expires_at IS NOT NULL AND status_changed_at IS NULL)
      OR (relationship_status IN ('ACCEPTED', 'EXPIRED', 'REJECTED') AND status_changed_at IS NOT NULL)
    ),

  CONSTRAINT ck_emergency_contacts_expires_after_created
    CHECK (expires_at IS NULL OR expires_at > created_at),

  CONSTRAINT ck_emergency_contacts_status_changed_after_created
    CHECK (status_changed_at IS NULL OR status_changed_at >= created_at),

  CONSTRAINT ck_emergency_contacts_updated_after_created
    CHECK (updated_at >= created_at)
);
