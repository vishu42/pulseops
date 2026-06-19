package config

import (
	"os"
	"strconv"
	"strings"
	"time"
)

type Config struct {
	HTTPAddr          string
	DatabaseURL       string
	KafkaBrokers      []string
	CheckJobsTopic    string
	CheckResultsTopic string
	ConsumerGroup     string
	SchedulerBatch    int
	SchedulerTick     time.Duration
	CheckerTimeout    time.Duration
}

func Load() Config {
	return Config{
		HTTPAddr:          env("HTTP_ADDR", ":8081"),
		DatabaseURL:       env("DATABASE_URL", "postgres://pulseops:pulseops@localhost:5432/pulseops?sslmode=disable"),
		KafkaBrokers:      splitCSV(env("KAFKA_BROKERS", "localhost:9092")),
		CheckJobsTopic:    env("CHECK_JOBS_TOPIC", "pulseops.url-check-jobs.v1"),
		CheckResultsTopic: env("CHECK_RESULTS_TOPIC", "pulseops.url-check-results.v1"),
		ConsumerGroup:     env("CONSUMER_GROUP", "pulseops-dev"),
		SchedulerBatch:    envInt("SCHEDULER_BATCH", 100),
		SchedulerTick:     envDuration("SCHEDULER_TICK", 10*time.Second),
		CheckerTimeout:    envDuration("CHECKER_TIMEOUT", 5*time.Second),
	}
}

func env(key string, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func envInt(key string, fallback int) int {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func envDuration(key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	parsed, err := time.ParseDuration(value)
	if err == nil {
		return parsed
	}
	seconds, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return time.Duration(seconds) * time.Second
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}
