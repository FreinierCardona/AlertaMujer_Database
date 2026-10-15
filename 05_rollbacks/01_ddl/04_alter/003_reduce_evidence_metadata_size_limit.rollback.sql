ALTER TABLE emergency.emergency_evidences
  DROP CONSTRAINT ck_emergency_evidences_file_size_bytes_range;

ALTER TABLE emergency.emergency_evidences
  ADD CONSTRAINT ck_emergency_evidences_file_size_bytes_range
    CHECK (file_size_bytes BETWEEN 1 AND 1048576);
