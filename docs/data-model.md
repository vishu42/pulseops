# Data Model

## Entities

### `companies`

Groups monitored URLs under a customer/company.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID/ULID | Primary key |
| `name` | text | Display name |
| `slug` | text | Unique URL-safe identifier |
| `created_at` | timestamptz | Insert timestamp |
| `updated_at` | timestamptz | Update timestamp |

### `monitored_urls`

URLs that should be probed.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID/ULID | Primary key |
| `company_id` | UUID/ULID | Foreign key to `companies` |
| `url` | text | Full URL |
| `normalized_url` | text | Lowercase host, normalized path/query for search/dedup |
| `method` | text | Default `GET` |
| `timeout_ms` | integer | Default `5000` |
| `check_interval_seconds` | integer | Default `60` |
| `expected_status_min` | integer | Default `200` |
| `expected_status_max` | integer | Default `399` |
| `is_active` | boolean | Scheduler ignores inactive URLs |
| `next_check_at` | timestamptz | Scheduler due timestamp |
| `created_at` | timestamptz | Insert timestamp |
| `updated_at` | timestamptz | Update timestamp |

Indexes:

- `(company_id, normalized_url)` unique.
- `(is_active, next_check_at)` for scheduler scans.
- Full-text or trigram index on `normalized_url` for URL search.

### `url_latest_status`

Fast dashboard reads without scanning history.

| Column | Type | Notes |
| --- | --- | --- |
| `url_id` | UUID/ULID | Primary key |
| `company_id` | UUID/ULID | Denormalized for filters |
| `last_check_id` | UUID/ULID | Idempotency trace |
| `outcome` | text | `up`, `down`, or `error` |
| `status_code` | integer | Nullable for network errors |
| `latency_ms` | integer | Nullable for early failures |
| `error_type` | text | Nullable |
| `checked_at` | timestamptz | Last probe time |
| `updated_at` | timestamptz | Write timestamp |

### `url_check_history`

Hot check history for quick 60-day access.

Partition by day or week on `checked_at`.

| Column | Type | Notes |
| --- | --- | --- |
| `check_id` | UUID/ULID | Primary/idempotency key |
| `company_id` | UUID/ULID | Query filter |
| `url_id` | UUID/ULID | Query filter |
| `outcome` | text | `up`, `down`, or `error` |
| `status_code` | integer | Nullable |
| `latency_ms` | integer | Nullable |
| `error_type` | text | Nullable |
| `error_message` | text | Nullable, capped length |
| `checked_at` | timestamptz | Probe timestamp |
| `created_at` | timestamptz | Insert timestamp |

Indexes:

- `(company_id, checked_at desc)`
- `(url_id, checked_at desc)`
- `(outcome, checked_at desc)` if filtering outages becomes common

### `archive_manifests`

Tracks cold storage exports.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | UUID/ULID | Primary key |
| `partition_name` | text | Hot partition exported |
| `object_key` | text | S3 object key |
| `format` | text | `parquet` or `ndjson.gz` |
| `record_count` | bigint | Exported records |
| `min_checked_at` | timestamptz | Range start |
| `max_checked_at` | timestamptz | Range end |
| `created_at` | timestamptz | Export timestamp |

## Retention Rule

Keep `url_check_history` partitions where `checked_at >= now() - interval '60 days'`.

Archive and remove older partitions after the export manifest is written and verified.

