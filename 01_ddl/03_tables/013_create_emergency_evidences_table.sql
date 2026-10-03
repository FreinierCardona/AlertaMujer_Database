CREATE TABLE emergency.emergency_evidences (
  evidence_id         UUID        NOT NULL DEFAULT gen_random_uuid(),
  emergency_id        UUID        NOT NULL,
  evidence_sequence   INTEGER     NOT NULL,
  file_reference      TEXT        NOT NULL,
  original_file_name  TEXT,
  mime_type           VARCHAR(10) NOT NULL,
  original_mime_type  TEXT,
  file_size_bytes     INTEGER     NOT NULL,
  captured_at         TIMESTAMPTZ,
  received_at         TIMESTAMPTZ NOT NULL,

  CONSTRAINT pk_emergency_evidences
    PRIMARY KEY (evidence_id),

  CONSTRAINT uq_emergency_evidences_file_reference
    UNIQUE (file_reference),

  CONSTRAINT uq_emergency_evidences_emergency_sequence
    UNIQUE (emergency_id, evidence_sequence),

  CONSTRAINT fk_emergency_evidences_emergency
    FOREIGN KEY (emergency_id)
    REFERENCES emergency.emergencies (emergency_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_emergency_evidences_sequence_range
    CHECK (evidence_sequence BETWEEN 1 AND 10),

  CONSTRAINT ck_emergency_evidences_file_reference_not_blank
    CHECK (btrim(file_reference) <> ''),

  CONSTRAINT ck_emergency_evidences_mime_type
    CHECK (mime_type = 'image/webp'),

  CONSTRAINT ck_emergency_evidences_file_size_bytes_range
    CHECK (file_size_bytes BETWEEN 1 AND 1048576)
);
