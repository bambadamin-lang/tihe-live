-- Extensions the application relies on. Created at first database init so migrations can
-- assume they exist.

-- pg_trgm: fuzzy and substring matching. This is what carries Persian search, since
-- PostgreSQL has no Persian stemmer. See docs/07-data-model.md.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- unaccent: strips diacritics. Used inside normalize_fa().
CREATE EXTENSION IF NOT EXISTS unaccent;

-- pgcrypto: gen_random_bytes() for tokens generated in SQL.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
