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

The repo includes a local development compose file. Start the API/UI and dependencies with:

```sh
docker compose up --build
```

Services:

- PulseOps UI/API on `localhost:8081`
- Scheduler worker
- Status checker worker
- Status writer worker
- PostgreSQL on `localhost:5432`
- Redpanda Kafka-compatible broker on `localhost:9092`
- Redpanda Console on `localhost:8080`
- MinIO on `localhost:9000`
- MinIO Console on `localhost:9001`

Open the UI:

```text
http://localhost:8081
```

For a fresh Postgres volume, the schema is applied automatically from `db/schema.sql`.
Kafka topics are created automatically by the `kafka-topics` one-shot Compose service.

Apply the initial database schema:

```sh
docker compose exec -T postgres psql -U pulseops -d pulseops < db/schema.sql
```

You only need the manual schema command if you already had a Postgres volume before schema initialization was added.

## Services

The first runnable services live under `cmd/`:

- `cmd/api-server`: REST API for company and URL CRUD.
- `cmd/scheduler`: claims due URLs from Postgres and emits Kafka check jobs.
- `cmd/status-checker`: consumes Kafka check jobs, probes URLs, and emits check results.
- `cmd/status-writer`: consumes check results and writes hot history/latest status.

For local Go development without Docker, run them in separate terminals:

```sh
make run-api
make run-scheduler
make run-checker
make run-writer
```

The API server also serves the simple web UI:

```text
http://localhost:8081
```

Click a monitor row in the UI to inspect latest probe status and 5-minute probe averages. Results appear after the scheduler, checker, and writer have processed at least one check.

## Docs

- [Architecture](docs/architecture.md)
- [AWS Architecture](docs/aws.md)
- [AWS CLI Infrastructure Scripts](scripts/aws/README.md)
- [Kafka Topics](docs/kafka-topics.md)
- [Data Model](docs/data-model.md)
- [API Draft](docs/api.md)
