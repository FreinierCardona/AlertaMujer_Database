-- HU-DB-027 / ADR-006: FCM data is intentionally removed with these tables.
-- This change is scheduled only with a Backend that no longer reads or writes
-- notification.*. It does not affect the emergency/contact source of truth.
--
-- The attempt table owns the foreign key to the device-token table. Dropping a
-- table removes its table-specific privileges and indexes.
DROP TABLE IF EXISTS notification.emergency_notification_attempts;
DROP TABLE IF EXISTS notification.user_device_tokens;

-- Do not use CASCADE: the schema must be empty after removing FCM-only objects.
DROP SCHEMA IF EXISTS notification;
