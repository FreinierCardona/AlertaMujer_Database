CREATE FUNCTION identity.bootstrap_entity_admin(
  p_username    TEXT,
  p_first_names TEXT,
  p_last_names  TEXT,
  p_email       TEXT,
  p_phone       TEXT,
  p_password    TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, public, identity
AS $bootstrap$
DECLARE
  existing_admin         identity.users%ROWTYPE;
  existing_password_hash VARCHAR(255);
  created_user_id        UUID;
BEGIN
  IF p_username IS NULL
     OR p_username <> btrim(p_username)
     OR p_username <> lower(p_username)
     OR p_username !~ '^@[a-z0-9][a-z0-9_]{1,18}[a-z0-9]$'
     OR p_first_names IS NULL
     OR p_first_names <> btrim(p_first_names)
     OR char_length(p_first_names) NOT BETWEEN 1 AND 100
     OR p_last_names IS NULL
     OR p_last_names <> btrim(p_last_names)
     OR char_length(p_last_names) NOT BETWEEN 1 AND 100
     OR p_email IS NULL
     OR p_email <> btrim(p_email)
     OR p_email <> lower(p_email)
     OR char_length(p_email) > 254
     OR p_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
     OR p_phone IS NULL
     OR p_phone !~ '^3[0-9]{9}$'
     OR p_password IS NULL
     OR octet_length(p_password) NOT BETWEEN 12 AND 72
     OR p_password !~ '[A-Z]'
     OR p_password !~ '[0-9]'
     OR p_password !~ '[^A-Za-z0-9]' THEN
    RAISE EXCEPTION USING
      ERRCODE = '22023',
      MESSAGE = 'Bootstrap entity administrator configuration is invalid.';
  END IF;

  PERFORM pg_advisory_xact_lock(294902901);

  SELECT *
    INTO existing_admin
    FROM identity.users
   WHERE role = 'ENTITY_ADMIN'
   FOR UPDATE;

  IF FOUND THEN
    SELECT password_hash
      INTO existing_password_hash
      FROM identity.user_credentials
     WHERE user_id = existing_admin.user_id
     FOR UPDATE;

    IF NOT FOUND
       OR existing_admin.username::TEXT <> p_username
       OR existing_admin.first_names <> p_first_names
       OR existing_admin.last_names <> p_last_names
       OR existing_admin.email::TEXT <> p_email
       OR existing_admin.phone <> p_phone
       OR existing_admin.account_status <> 'ENABLED'
       OR existing_admin.account_origin <> 'ADMIN_CREATED'
       OR existing_admin.accepted_terms_at IS NOT NULL
       OR existing_password_hash !~ '^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'Bootstrap entity administrator configuration conflicts with existing data.';
    END IF;

    IF public.crypt(p_password, existing_password_hash) <> existing_password_hash THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'Bootstrap entity administrator configuration conflicts with existing data.';
    END IF;

    RETURN 'UNCHANGED';
  END IF;

  PERFORM 1
    FROM identity.users
   WHERE username = p_username
      OR email = p_email
      OR phone = p_phone
   FOR KEY SHARE;

  IF FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Bootstrap entity administrator configuration conflicts with existing data.';
  END IF;

  BEGIN
    INSERT INTO identity.users (
      username,
      first_names,
      last_names,
      email,
      phone,
      role,
      account_status,
      account_origin
    ) VALUES (
      p_username,
      p_first_names,
      p_last_names,
      p_email,
      p_phone,
      'ENTITY_ADMIN',
      'ENABLED',
      'ADMIN_CREATED'
    )
    RETURNING user_id INTO created_user_id;

    INSERT INTO identity.user_credentials (
      user_id,
      password_hash
    ) VALUES (
      created_user_id,
      public.crypt(p_password, public.gen_salt('bf', 10))
    );
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'Bootstrap entity administrator configuration conflicts with existing data.';
  END;

  RETURN 'CREATED';
END;
$bootstrap$;

REVOKE ALL ON FUNCTION identity.bootstrap_entity_admin(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
