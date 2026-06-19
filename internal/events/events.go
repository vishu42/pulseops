package events

import "time"

type URLCheckJob struct {
	CheckID           string    `json:"check_id"`
	CompanyID         string    `json:"company_id"`
	URLID             string    `json:"url_id"`
	URL               string    `json:"url"`
	Method            string    `json:"method"`
	TimeoutMS         int       `json:"timeout_ms"`
	ExpectedStatusMin int       `json:"expected_status_min"`
	ExpectedStatusMax int       `json:"expected_status_max"`
	ScheduledAt       time.Time `json:"scheduled_at"`
	Attempt           int       `json:"attempt"`
}

type URLCheckResult struct {
	CheckID      string    `json:"check_id"`
	CompanyID    string    `json:"company_id"`
	URLID        string    `json:"url_id"`
	URL          string    `json:"url"`
	Outcome      string    `json:"outcome"`
	StatusCode   *int      `json:"status_code"`
	LatencyMS    *int64    `json:"latency_ms"`
	ErrorType    *string   `json:"error_type"`
	ErrorMessage *string   `json:"error_message"`
	CheckedAt    time.Time `json:"checked_at"`
	WorkerID     string    `json:"worker_id"`
}

const (
	OutcomeUp    = "up"
	OutcomeDown  = "down"
	OutcomeError = "error"
)
