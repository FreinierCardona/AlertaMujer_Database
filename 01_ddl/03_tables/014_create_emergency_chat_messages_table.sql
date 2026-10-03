CREATE TABLE emergency.emergency_chat_messages (
  chat_message_id   BIGINT       GENERATED ALWAYS AS IDENTITY,
  client_message_id UUID         NOT NULL,
  emergency_id      UUID         NOT NULL,
  sender_user_id    UUID         NOT NULL,
  content           VARCHAR(500) NOT NULL,
  sent_at           TIMESTAMPTZ  NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT pk_emergency_chat_messages
    PRIMARY KEY (chat_message_id),

  CONSTRAINT uq_emergency_chat_messages_emergency_client_message
    UNIQUE (emergency_id, client_message_id),

  CONSTRAINT fk_emergency_chat_messages_emergency
    FOREIGN KEY (emergency_id)
    REFERENCES emergency.emergencies (emergency_id)
    ON DELETE CASCADE,

  CONSTRAINT fk_emergency_chat_messages_sender_user
    FOREIGN KEY (sender_user_id)
    REFERENCES identity.users (user_id)
    ON DELETE CASCADE,

  CONSTRAINT ck_emergency_chat_messages_content_not_blank
    CHECK (btrim(content) <> '')
);
