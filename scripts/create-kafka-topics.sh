#!/usr/bin/env sh
set -eu

BROKERS="${BROKERS:-localhost:9092}"
PARTITIONS="${PARTITIONS:-12}"
DLQ_PARTITIONS="${DLQ_PARTITIONS:-3}"

create_topic() {
  topic="$1"
  if rpk topic describe "$topic" --brokers "$BROKERS" >/dev/null 2>&1; then
    echo "topic already exists: $topic"
    return 0
  fi
  rpk topic create "$@"
}

create_topic pulseops.url-check-jobs.v1 \
  --brokers "$BROKERS" \
  --partitions "$PARTITIONS" \
  --replicas 1 \
  --topic-config retention.ms=86400000

create_topic pulseops.url-check-results.v1 \
  --brokers "$BROKERS" \
  --partitions "$PARTITIONS" \
  --replicas 1 \
  --topic-config retention.ms=604800000

create_topic pulseops.url-check-jobs.dlq.v1 \
  --brokers "$BROKERS" \
  --partitions "$DLQ_PARTITIONS" \
  --replicas 1 \
  --topic-config retention.ms=1209600000

create_topic pulseops.url-check-results.dlq.v1 \
  --brokers "$BROKERS" \
  --partitions "$DLQ_PARTITIONS" \
  --replicas 1 \
  --topic-config retention.ms=1209600000
