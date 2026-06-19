# Kafka Topics

## Naming

All topics use this format:

```text
pulseops.<domain-event>.v<schema-version>
```

The initial version is `v1`. Breaking payload changes create a new versioned topic.

## `pulseops.url-check-jobs.v1`

Produced by `scheduler`.

Consumed by `status-checker` workers.

Partition key:

```text
url_id
```

Keeping `url_id` as the key preserves order for checks of the same URL while still allowing horizontal worker scale.

Payload:

```json
{
  "check_id": "01JZ2E3M4N5P6Q7R8S9T0V1W2X",
  "company_id": "01JZ2DTS4W3V4B5N6M7K8J9H0Q",
  "url_id": "01JZ2E0EWPK4P4T2TFTHV2AR5R",
  "url": "https://example.com/health",
  "method": "GET",
  "timeout_ms": 5000,
  "expected_status_min": 200,
  "expected_status_max": 399,
  "scheduled_at": "2026-06-18T17:50:00Z",
  "attempt": 1
}
```

Headers:

- `event_type`: `url_check_job`
- `schema_version`: `1`
- `trace_id`: request or scheduler trace id

## `pulseops.url-check-results.v1`

Produced by `status-checker`.

Consumed by `status-writer`.

Partition key:

```text
url_id
```

Payload:

```json
{
  "check_id": "01JZ2E3M4N5P6Q7R8S9T0V1W2X",
  "company_id": "01JZ2DTS4W3V4B5N6M7K8J9H0Q",
  "url_id": "01JZ2E0EWPK4P4T2TFTHV2AR5R",
  "url": "https://example.com/health",
  "outcome": "up",
  "status_code": 200,
  "latency_ms": 142,
  "error_type": null,
  "error_message": null,
  "checked_at": "2026-06-18T17:50:01Z",
  "worker_id": "checker-7"
}
```

`outcome` values:

- `up`: received expected HTTP status range.
- `down`: received a response outside the expected range.
- `error`: DNS, TCP, TLS, timeout, or other request failure.

Headers:

- `event_type`: `url_check_result`
- `schema_version`: `1`
- `trace_id`: copied from job header

## Dead-Letter Topics

Each consumer has a matching dead-letter topic:

- `pulseops.url-check-jobs.dlq.v1`
- `pulseops.url-check-results.dlq.v1`

Messages should be sent to a DLQ after bounded retry attempts with headers explaining the failure:

- `failed_consumer`
- `failure_reason`
- `failed_at`

## Topic Configuration

Suggested local/default settings:

| Topic | Partitions | Retention | Cleanup |
| --- | ---: | --- | --- |
| `pulseops.url-check-jobs.v1` | 12 | 24 hours | delete |
| `pulseops.url-check-results.v1` | 12 | 7 days | delete |
| `*.dlq.v1` | 3 | 14 days | delete |

Production partition counts should be chosen from expected check volume and worker count.

