# API Draft

Base path:

```text
/api/v1
```

## Companies

### Create Company

```http
POST /api/v1/companies
Content-Type: application/json
```

```json
{
  "name": "Acme",
  "slug": "acme"
}
```

### List Companies

```http
GET /api/v1/companies
```

### Get Company

```http
GET /api/v1/companies/{company_id}
```

## URLs

### Add URL

```http
POST /api/v1/companies/{company_id}/urls
Content-Type: application/json
```

```json
{
  "url": "https://example.com/health",
  "method": "GET",
  "timeout_ms": 5000,
  "check_interval_seconds": 60,
  "expected_status_min": 200,
  "expected_status_max": 399
}
```

### List Company URLs

```http
GET /api/v1/companies/{company_id}/urls
```

Query params:

- `q`: optional URL search text.
- `status`: optional `up`, `down`, or `error`.
- `limit`: default `50`.
- `cursor`: pagination cursor.

### Get URL

```http
GET /api/v1/urls/{url_id}
```

### Update URL

```http
PATCH /api/v1/urls/{url_id}
Content-Type: application/json
```

```json
{
  "is_active": true,
  "timeout_ms": 3000,
  "check_interval_seconds": 120
}
```

## History

### Get URL History

```http
GET /api/v1/urls/{url_id}/history
```

Query params:

- `from`: ISO timestamp, defaults to 24 hours ago.
- `to`: ISO timestamp, defaults to now.
- `limit`: default `500`.
- `cursor`: pagination cursor.

The API should reject hot history queries older than 60 days unless an archive retrieval path has been implemented.

## Search

### Search URLs

```http
GET /api/v1/search/urls?q=example.com
```

Query params:

- `company_id`: optional company filter.
- `q`: required URL text.
- `limit`: default `50`.
- `cursor`: pagination cursor.

## Status Shape

URL responses include latest status:

```json
{
  "id": "01JZ2E0EWPK4P4T2TFTHV2AR5R",
  "company_id": "01JZ2DTS4W3V4B5N6M7K8J9H0Q",
  "url": "https://example.com/health",
  "is_active": true,
  "latest_status": {
    "outcome": "up",
    "status_code": 200,
    "latency_ms": 142,
    "checked_at": "2026-06-18T17:50:01Z"
  }
}
```

