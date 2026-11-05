-- Conserva las ubicaciones recibidas y la precisión reportada por el dispositivo.
CREATE TABLE emergency.emergency_locations (

  -- Identidad de la muestra y emergencia asociada.
  location_id      UUID          NOT NULL DEFAULT gen_random_uuid(),
  emergency_id     UUID          NOT NULL,

  -- Coordenadas geográficas; la precisión es opcional y se expresa en metros.
  latitude         NUMERIC(9,6)  NOT NULL,
  longitude        NUMERIC(9,6)  NOT NULL,
  accuracy_meters  NUMERIC,

  -- Distingue la captura en el dispositivo de la recepción en el servidor.
  captured_at      TIMESTAMPTZ   NOT NULL,
  received_at      TIMESTAMPTZ   NOT NULL,

  CONSTRAINT pk_emergency_locations
    PRIMARY KEY (location_id),

  CONSTRAINT fk_emergency_locations_emergency
    FOREIGN KEY (emergency_id)
    REFERENCES emergency.emergencies (emergency_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_emergency_locations_latitude_range
    CHECK (latitude BETWEEN -90 AND 90),

  CONSTRAINT ck_emergency_locations_longitude_range
    CHECK (longitude BETWEEN -180 AND 180),

  CONSTRAINT ck_emergency_locations_accuracy_meters_nonnegative
    CHECK (accuracy_meters IS NULL OR accuracy_meters >= 0)
);
