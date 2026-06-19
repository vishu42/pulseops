package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net"
	"net/http"
	"os"
	"time"

	"github.com/segmentio/kafka-go"
	"github.com/vishu42/pulseops/internal/config"
	"github.com/vishu42/pulseops/internal/events"
	"github.com/vishu42/pulseops/internal/kafkaio"
)

func main() {
	cfg := config.Load()
	workerID, _ := os.Hostname()
	if workerID == "" {
		workerID = "status-checker"
	}

	reader := kafkaio.NewReader(cfg.KafkaBrokers, cfg.CheckJobsTopic, cfg.ConsumerGroup+"-status-checker")
	defer reader.Close()

	producer := kafkaio.NewProducer(cfg.KafkaBrokers, cfg.CheckResultsTopic)
	defer producer.Close()

	client := &http.Client{Timeout: cfg.CheckerTimeout}

	log.Printf("status-checker started worker_id=%s", workerID)
	for {
		message, err := reader.FetchMessage(context.Background())
		if err != nil {
			log.Printf("fetch job: %v", err)
			continue
		}

		var job events.URLCheckJob
		if err := json.Unmarshal(message.Value, &job); err != nil {
			log.Printf("decode job offset=%d: %v", message.Offset, err)
			commit(reader, message)
			continue
		}

		result := checkURL(client, job, workerID)
		if err := producer.PublishJSON(context.Background(), job.URLID, result, map[string]string{
			"event_type":     "url_check_result",
			"schema_version": "1",
			"trace_id":       job.CheckID,
		}); err != nil {
			log.Printf("publish result check_id=%s: %v", job.CheckID, err)
			continue
		}

		commit(reader, message)
		log.Printf("checked url_id=%s outcome=%s", job.URLID, result.Outcome)
	}
}

func checkURL(client *http.Client, job events.URLCheckJob, workerID string) events.URLCheckResult {
	start := time.Now()
	req, err := http.NewRequest(job.Method, job.URL, nil)
	if err != nil {
		return errorResult(job, workerID, "invalid_request", err, start)
	}
	req.Header.Set("User-Agent", "PulseOps/0.1")

	resp, err := client.Do(req)
	if err != nil {
		return errorResult(job, workerID, classifyError(err), err, start)
	}
	defer resp.Body.Close()

	latency := time.Since(start).Milliseconds()
	statusCode := resp.StatusCode
	outcome := events.OutcomeDown
	if statusCode >= job.ExpectedStatusMin && statusCode <= job.ExpectedStatusMax {
		outcome = events.OutcomeUp
	}

	return events.URLCheckResult{
		CheckID:    job.CheckID,
		CompanyID:  job.CompanyID,
		URLID:      job.URLID,
		URL:        job.URL,
		Outcome:    outcome,
		StatusCode: &statusCode,
		LatencyMS:  &latency,
		CheckedAt:  time.Now().UTC(),
		WorkerID:   workerID,
	}
}

func errorResult(job events.URLCheckJob, workerID string, errorType string, err error, start time.Time) events.URLCheckResult {
	latency := time.Since(start).Milliseconds()
	message := err.Error()
	return events.URLCheckResult{
		CheckID:      job.CheckID,
		CompanyID:    job.CompanyID,
		URLID:        job.URLID,
		URL:          job.URL,
		Outcome:      events.OutcomeError,
		LatencyMS:    &latency,
		ErrorType:    &errorType,
		ErrorMessage: &message,
		CheckedAt:    time.Now().UTC(),
		WorkerID:     workerID,
	}
}

func classifyError(err error) string {
	var dnsErr *net.DNSError
	if errors.As(err, &dnsErr) {
		return "dns"
	}
	if os.IsTimeout(err) {
		return "timeout"
	}
	return "request"
}

func commit(reader *kafka.Reader, message kafka.Message) {
	if err := reader.CommitMessages(context.Background(), message); err != nil {
		log.Printf("commit offset=%d: %v", message.Offset, err)
	}
}
