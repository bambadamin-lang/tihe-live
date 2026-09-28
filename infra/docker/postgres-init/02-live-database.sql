-- services/live keeps its tables in its own database on the same server (ADR-0012), so neither
-- service's migrations can touch the other's tables. Runs only on first init of the volume; on
-- an existing volume, run these two statements by hand.
-- Inherits the cluster's fa-IR ICU collation from template1.
CREATE DATABASE tihe_live;

\connect tihe_live
CREATE EXTENSION IF NOT EXISTS pgcrypto;
