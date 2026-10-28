-- Facilita obtener la ubicación recibida más recientemente para una emergencia.
CREATE INDEX ix_emergency_locations_emergency_received_at
  ON emergency.emergency_locations (emergency_id, received_at DESC);
