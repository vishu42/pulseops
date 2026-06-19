CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE companies (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE monitored_urls (
  id UUID PRIMARY KEY,
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  url TEXT NOT NULL,
  normalized_url TEXT NOT NULL,
  method TEXT NOT NULL DEFAULT 'GET',
  timeout_ms INTEGER NOT NULL DEFAULT 5000 CHECK (timeout_ms > 0),
  check_interval_seconds INTEGER NOT NULL DEFAULT 60 CHECK (check_interval_seconds > 0),
  expected_status_min INTEGER NOT NULL DEFAULT 200,
  expected_status_max INTEGER NOT NULL DEFAULT 399,
  is_active BOOLEAN NOT NULL DEFAULT true,
  next_check_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT monitored_urls_expected_status_range
    CHECK (expected_status_min <= expected_status_max),
  CONSTRAINT monitored_urls_company_normalized_unique
    UNIQUE (company_id, normalized_url)
);

CREATE INDEX monitored_urls_due_idx
  ON monitored_urls (is_active, next_check_at);

CREATE INDEX monitored_urls_normalized_trgm_idx
  ON monitored_urls USING gin (normalized_url gin_trgm_ops);

CREATE TABLE url_latest_status (
  url_id UUID PRIMARY KEY REFERENCES monitored_urls(id) ON DELETE CASCADE,
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  last_check_id UUID NOT NULL,
  outcome TEXT NOT NULL CHECK (outcome IN ('up', 'down', 'error')),
  status_code INTEGER,
  latency_ms INTEGER,
  error_type TEXT,
  checked_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX url_latest_status_company_idx
  ON url_latest_status (company_id, checked_at DESC);

CREATE TABLE url_check_history (
  check_id UUID PRIMARY KEY,
  company_id UUID NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  url_id UUID NOT NULL REFERENCES monitored_urls(id) ON DELETE CASCADE,
  outcome TEXT NOT NULL CHECK (outcome IN ('up', 'down', 'error')),
  status_code INTEGER,
  latency_ms INTEGER,
  error_type TEXT,
  error_message TEXT,
  checked_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX url_check_history_company_checked_idx
  ON url_check_history (company_id, checked_at DESC);

CREATE INDEX url_check_history_url_checked_idx
  ON url_check_history (url_id, checked_at DESC);

CREATE INDEX url_check_history_outcome_checked_idx
  ON url_check_history (outcome, checked_at DESC);

CREATE TABLE archive_manifests (
  id UUID PRIMARY KEY,
  partition_name TEXT NOT NULL,
  object_key TEXT NOT NULL UNIQUE,
  format TEXT NOT NULL CHECK (format IN ('parquet', 'ndjson.gz')),
  record_count BIGINT NOT NULL CHECK (record_count >= 0),
  min_checked_at TIMESTAMPTZ NOT NULL,
  max_checked_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

