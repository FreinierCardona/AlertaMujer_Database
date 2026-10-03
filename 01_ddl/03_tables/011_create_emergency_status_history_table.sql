CREATE TABLE emergency.emergency_status_history (
  emergency_status_history_id UUID        NOT NULL DEFAULT gen_random_uuid(),
  emergency_id                UUID        NOT NULL,
  sequence_no                 INTEGER     NOT NULL,
  previous_status             VARCHAR(11),
  new_status                  VARCHAR(11) NOT NULL,
  actor_user_id               UUID,
  cause                       TEXT,
  occurred_at                 TIMESTAMPTZ NOT NULL,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT pk_emergency_status_history
    PRIMARY KEY (emergency_status_history_id),

  CONSTRAINT uq_emergency_status_history_emergency_sequence
    UNIQUE (emergency_id, sequence_no),

  CONSTRAINT fk_emergency_status_history_emergency
    FOREIGN KEY (emergency_id)
    REFERENCES emergency.emergencies (emergency_id)
    ON DELETE CASCADE,

  CONSTRAINT fk_emergency_status_history_actor_user
    FOREIGN KEY (actor_user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_emergency_status_history_sequence_no_positive
    CHECK (sequence_no > 0),

  CONSTRAINT ck_emergency_status_history_previous_status
    CHECK (
      previous_status IS NULL
      OR previous_status IN ('ACTIVE', 'IN_PROGRESS', 'OFFLINE', 'FINALIZED')
    ),

  CONSTRAINT ck_emergency_status_history_new_status
    CHECK (new_status IN ('ACTIVE', 'IN_PROGRESS', 'OFFLINE', 'FINALIZED')),

  CONSTRAINT ck_emergency_status_history_initial_transition
    CHECK (
      (sequence_no = 1 AND previous_status IS NULL AND new_status = 'ACTIVE')
      OR (sequence_no > 1 AND previous_status IS NOT NULL)
    ),

  CONSTRAINT ck_emergency_status_history_cause_not_blank
    CHECK (cause IS NULL OR btrim(cause) <> '')
);
