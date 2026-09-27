-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- CreateTable
CREATE TABLE "live_classes" (
    "id" TEXT NOT NULL,
    "course_id" TEXT NOT NULL,
    "section_id" TEXT,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "teacher_id" TEXT NOT NULL,
    "scheduled_start_at" TIMESTAMPTZ(3),
    "duration_minutes" INTEGER NOT NULL,
    "settings" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMPTZ(3) NOT NULL,

    CONSTRAINT "live_classes_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "live_sessions" (
    "id" TEXT NOT NULL,
    "class_id" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "started_at" TIMESTAMPTZ(3) NOT NULL,
    "ended_at" TIMESTAMPTZ(3),
    "egress_id" TEXT,
    "recording_started_at" TIMESTAMPTZ(3),
    "recording_ended_at" TIMESTAMPTZ(3),
    "recording_error" TEXT,
    "peak_participants" INTEGER NOT NULL DEFAULT 0,
    "final_snapshot" JSONB,

    CONSTRAINT "live_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "live_attendance" (
    "session_id" TEXT NOT NULL,
    "user_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "role" TEXT NOT NULL,
    "first_joined_at" TIMESTAMPTZ(3) NOT NULL,
    "last_left_at" TIMESTAMPTZ(3),
    "seconds_present" INTEGER NOT NULL DEFAULT 0,
    "open_since" TIMESTAMPTZ(3),
    "join_count" INTEGER NOT NULL DEFAULT 0,
    "capture_attempts" INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT "live_attendance_pkey" PRIMARY KEY ("session_id","user_id")
);

-- CreateTable
CREATE TABLE "saved_layouts" (
    "id" TEXT NOT NULL,
    "owner_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "pods" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "saved_layouts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "live_audit_events" (
    "id" TEXT NOT NULL,
    "session_id" TEXT NOT NULL,
    "actor_id" TEXT,
    "target_id" TEXT,
    "kind" TEXT NOT NULL,
    "detail" JSONB NOT NULL,
    "created_at" TIMESTAMPTZ(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "live_audit_events_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "live_classes_course_id_idx" ON "live_classes"("course_id");

-- CreateIndex
CREATE INDEX "live_classes_teacher_id_idx" ON "live_classes"("teacher_id");

-- CreateIndex
CREATE UNIQUE INDEX "live_sessions_egress_id_key" ON "live_sessions"("egress_id");

-- CreateIndex
CREATE INDEX "live_sessions_class_id_status_idx" ON "live_sessions"("class_id", "status");

-- CreateIndex
CREATE INDEX "saved_layouts_owner_id_idx" ON "saved_layouts"("owner_id");

-- CreateIndex
CREATE INDEX "live_audit_events_session_id_created_at_idx" ON "live_audit_events"("session_id", "created_at");

-- CreateIndex
CREATE INDEX "live_audit_events_target_id_kind_idx" ON "live_audit_events"("target_id", "kind");

-- AddForeignKey
ALTER TABLE "live_sessions" ADD CONSTRAINT "live_sessions_class_id_fkey" FOREIGN KEY ("class_id") REFERENCES "live_classes"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "live_attendance" ADD CONSTRAINT "live_attendance_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "live_sessions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "live_audit_events" ADD CONSTRAINT "live_audit_events_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "live_sessions"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

