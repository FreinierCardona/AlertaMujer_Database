CREATE TABLE emergency.emergencies (
  emergency_id               UUID         NOT NULL DEFAULT gen_random_uuid(),
  user_id                    UUID         NOT NULL,
  status                     VARCHAR(11)  NOT NULL DEFAULT 'ACTIVE',
  previous_operational_status VARCHAR(11),
  last_heartbeat_at          TIMESTAMPTZ,
  message_snapshot           VARCHAR(500) NOT NULL,
  started_at                 TIMESTAMPTZ  NOT NULL,
  finalized_at               TIMESTAMPTZ,
  created_at                 TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at                 TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT pk_emergencies
    PRIMARY KEY (emergency_id),

  CONSTRAINT fk_emergencies_user
    FOREIGN KEY (user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_emergencies_status
    CHECK (status IN ('ACTIVE', 'IN_PROGRESS', 'OFFLINE', 'FINALIZED')),

  CONSTRAINT ck_emergencies_previous_operational_status
    CHECK (
      (status = 'OFFLINE' AND previous_operational_status IN ('ACTIVE', 'IN_PROGRESS'))
      OR (status <> 'OFFLINE' AND previous_operational_status IS NULL)
    ),

  CONSTRAINT ck_emergencies_message_snapshot_not_blank
    CHECK (btrim(message_snapshot) <> ''),

  CONSTRAINT ck_emergencies_finalized_at_matches_status
    CHECK (
      (status = 'FINALIZED' AND finalized_at IS NOT NULL)
      OR (status <> 'FINALIZED' AND finalized_at IS NULL)
    ),

  CONSTRAINT ck_emergencies_finalized_after_started
    CHECK (finalized_at IS NULL OR finalized_at >= started_at),

  CONSTRAINT ck_emergencies_updated_after_created
    CHECK (updated_at >= created_at)
);
