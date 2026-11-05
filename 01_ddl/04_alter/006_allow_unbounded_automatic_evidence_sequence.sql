-- La captura periódica conserva una secuencia positiva sin imponer un máximo fijo por alerta.
ALTER TABLE emergency.emergency_evidences
  DROP CONSTRAINT ck_emergency_evidences_sequence_range;

ALTER TABLE emergency.emergency_evidences
  ADD CONSTRAINT ck_emergency_evidences_sequence_range
    CHECK (evidence_sequence >= 1);

-- Cero representa que la aplicación no limita la cantidad de evidencias mientras la alerta siga abierta.
ALTER TABLE configuration.system_configuration
  DROP CONSTRAINT ck_system_configuration_max_evidence_count_positive;

ALTER TABLE configuration.system_configuration
  ADD CONSTRAINT ck_system_configuration_max_evidence_count_nonnegative
    CHECK (max_evidence_count >= 0);
