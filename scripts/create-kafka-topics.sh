#!/usr/bin/env sh
set -eu

BROKERS="${BROKERS:-localhost:9092}"
PARTITIONS="${PARTITIONS:-12}"
DLQ_PARTITIONS="${DLQ_PARTITIONS:-3}"

rpk topic create pulseops.url-check-jobs.v1 \
  --brokers "$BROKERS" \
  --partitions "$PARTITIONS" \
  --replicas 1 \
  --topic-config retention.ms=86400000

rpk topic create pulseops.url-check-results.v1 \
  --brokers "$BROKERS" \
  --partitions "$PARTITIONS" \
  --replicas 1 \
  --topic-config retention.ms=604800000

rpk topic create pulseops.url-check-jobs.dlq.v1 \
  --brokers "$BROKERS" \
  --partitions "$DLQ_PARTITIONS" \
  --replicas 1 \
  --topic-config retention.ms=1209600000

rpk topic create pulseops.url-check-results.dlq.v1 \
  --brokers "$BROKERS" \
  --partitions "$DLQ_PARTITIONS" \
  --replicas 1 \
  --topic-config retention.ms=1209600000

