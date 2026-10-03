CREATE TABLE audit.audit_logs (
  audit_log_id    UUID        NOT NULL DEFAULT gen_random_uuid(),
  actor_user_id   UUID,
  subject_user_id UUID,
  action          VARCHAR(22) NOT NULL,
  entity_type     TEXT        NOT NULL,
  entity_id       UUID        NOT NULL,
  result          VARCHAR(7)  NOT NULL,
  previous_state  JSONB,
  new_state       JSONB,
  description     VARCHAR(500),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  expires_at      TIMESTAMPTZ,

  CONSTRAINT pk_audit_logs
    PRIMARY KEY (audit_log_id),

  CONSTRAINT fk_audit_logs_actor_user
    FOREIGN KEY (actor_user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT fk_audit_logs_subject_user
    FOREIGN KEY (subject_user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_audit_logs_action
    CHECK (
      action IN (
        'ADMIN_LOGIN',
        'ALERT_VIEWED',
        'USER_PROFILE_VIEWED',
        'ALERT_STATUS_CHANGED',
        'ACCOUNT_STATUS_CHANGED'
      )
    ),

  CONSTRAINT ck_audit_logs_entity_type_not_blank
    CHECK (btrim(entity_type) <> ''),

  CONSTRAINT ck_audit_logs_result
    CHECK (result IN ('SUCCESS', 'FAILED')),

  CONSTRAINT ck_audit_logs_previous_state_object
    CHECK (previous_state IS NULL OR jsonb_typeof(previous_state) = 'object'),

  CONSTRAINT ck_audit_logs_new_state_object
    CHECK (new_state IS NULL OR jsonb_typeof(new_state) = 'object'),

  CONSTRAINT ck_audit_logs_description_not_blank
    CHECK (description IS NULL OR btrim(description) <> '')
);
