.PHONY: run-api run-scheduler run-checker run-writer test

run-api:
	go run ./cmd/api-server

run-scheduler:
	go run ./cmd/scheduler

run-checker:
	go run ./cmd/status-checker

run-writer:
	go run ./cmd/status-writer

test:
	go test ./...

