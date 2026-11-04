ALTER TABLE emergency.emergency_evidences
  DROP CONSTRAINT ck_emergency_evidences_sequence_range;

-- NOT VALID conserva evidencia histórica por encima de diez filas y vuelve a limitar inserciones nuevas.
ALTER TABLE emergency.emergency_evidences
  ADD CONSTRAINT ck_emergency_evidences_sequence_range
    CHECK (evidence_sequence BETWEEN 1 AND 10) NOT VALID;

ALTER TABLE configuration.system_configuration
  DROP CONSTRAINT ck_system_configuration_max_evidence_count_nonnegative;

ALTER TABLE configuration.system_configuration
  ADD CONSTRAINT ck_system_configuration_max_evidence_count_positive
    CHECK (max_evidence_count > 0);
