-- Cero desactiva el tope de aplicación para evidencias automáticas de alertas abiertas.
UPDATE configuration.system_configuration
   SET max_evidence_count = 0
 WHERE configuration_id = 1;
