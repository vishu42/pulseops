# PulseOps

PulseOps is a simple uptime monitor for grouping company URLs, probing them continuously, and keeping recent history fast while archiving older history cheaply.

## Product Scope

- Create companies and register URLs under each company.
- Probe URLs continuously from background workers.
- Keep the latest 60 days of check history in hot storage for quick UI access.
- Archive history older than 60 days to cold object storage.
- Search for a particular URL across companies.

## System Shape

The initial architecture follows the sketch in `docs/architecture.md`:

- `frontend`: UI for companies, URLs, search, and 60-day history.
- `api-server`: REST API for the UI and control plane.
- `scheduler`: periodically emits URL check jobs.
- `status-checker`: horizontally scalable workers that ping URLs.
- `status-writer`: consumes check results and persists them.
- `Kafka`: queue/event backbone for scheduling and status results.
- `PostgreSQL`: canonical relational database and hot history store.
- `S3-compatible object storage`: cold history archive.

## Local Infra

The repo includes a local development compose file:

```sh
docker compose up -d
```

Services:

- PostgreSQL on `localhost:5432`
- Redpanda Kafka-compatible broker on `localhost:9092`
- Redpanda Console on `localhost:8080`
- MinIO on `localhost:9000`
- MinIO Console on `localhost:9001`

Create Kafka topics after Redpanda is healthy:

```sh
docker compose exec redpanda sh -lc '/scripts/create-kafka-topics.sh'
```

Or run the script from a machine with `rpk` installed:

```sh
BROKERS=localhost:9092 scripts/create-kafka-topics.sh
```

Apply the initial database schema:

```sh
docker compose exec -T postgres psql -U pulseops -d pulseops < db/schema.sql
```

## Services

The first runnable services live under `cmd/`:

- `cmd/api-server`: REST API for company and URL CRUD.
- `cmd/scheduler`: claims due URLs from Postgres and emits Kafka check jobs.
- `cmd/status-checker`: consumes Kafka check jobs, probes URLs, and emits check results.
- `cmd/status-writer`: consumes check results and writes hot history/latest status.

Run them locally in separate terminals:

```sh
make run-api
make run-scheduler
make run-checker
make run-writer
```

## Docs

- [Architecture](docs/architecture.md)
- [Kafka Topics](docs/kafka-topics.md)
- [Data Model](docs/data-model.md)
- [API Draft](docs/api.md)
