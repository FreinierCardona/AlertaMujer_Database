-- HU-DB-027 / ADR-006: los datos FCM se eliminan intencionalmente junto con estas tablas.
-- Este cambio se programa solo con una versión de Backend que ya no lea ni escriba en
-- notification.*. No afecta a la fuente de verdad de emergencias y contactos.
--
-- La tabla de intentos contiene la clave foránea hacia la tabla de tokens de dispositivo. Eliminar una
-- tabla elimina sus permisos e índices específicos.
DROP TABLE IF EXISTS notification.emergency_notification_attempts;
DROP TABLE IF EXISTS notification.user_device_tokens;

-- No usar CASCADE: el esquema debe quedar vacío tras retirar los objetos exclusivos de FCM.
DROP SCHEMA IF EXISTS notification;
