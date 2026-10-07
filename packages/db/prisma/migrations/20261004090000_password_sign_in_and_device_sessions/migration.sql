-- Phone + password accounts (ADR-0013) and devices signed in at once (ADR-0014).
-- Hand-written: `prisma migrate diff` also proposes dropping the trigram indexes and the
-- search_text defaults from the init migration, which Prisma does not model. Those must stay.

-- Accounts sign in with a password now; SMS codes are gone.
ALTER TABLE "users"
  ADD COLUMN "password_hash" TEXT,
  ADD COLUMN "password_changed_at" TIMESTAMP(3),
  ADD COLUMN "must_change_password" BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN "max_devices" INTEGER,
  ADD CONSTRAINT "users_max_devices_range" CHECK ("max_devices" IS NULL OR "max_devices" BETWEEN 1 AND 20);

DROP TABLE "otp_codes";

-- The current sign-in on each device. A device counts towards the limit while it has one.
ALTER TABLE "devices"
  ADD COLUMN "session_id" TEXT,
  ADD COLUMN "session_started_at" TIMESTAMP(3),
  ADD COLUMN "session_expires_at" TIMESTAMP(3);

CREATE UNIQUE INDEX "devices_session_id_key" ON "devices"("session_id");
CREATE INDEX "devices_user_id_session_expires_at_idx" ON "devices"("user_id", "session_expires_at");

CREATE TABLE "login_attempts" (
    "id" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "ip" TEXT,
    "succeeded" BOOLEAN NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "login_attempts_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "login_attempts_phone_created_at_idx" ON "login_attempts"("phone", "created_at");
CREATE INDEX "login_attempts_ip_created_at_idx" ON "login_attempts"("ip", "created_at");

CREATE TABLE "settings" (
    "key" TEXT NOT NULL,
    "value" JSONB NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL,
    "updated_by" TEXT,

    CONSTRAINT "settings_pkey" PRIMARY KEY ("key")
);
