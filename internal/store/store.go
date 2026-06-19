package store

import (
	"context"
	"database/sql"
	"errors"
	"net/url"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/vishu42/pulseops/internal/events"
)

type Store struct {
	db *sql.DB
}

type Company struct {
	ID        string    `json:"id"`
	Name      string    `json:"name"`
	Slug      string    `json:"slug"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type MonitoredURL struct {
	ID                   string    `json:"id"`
	CompanyID            string    `json:"company_id"`
	URL                  string    `json:"url"`
	NormalizedURL        string    `json:"normalized_url"`
	Method               string    `json:"method"`
	TimeoutMS            int       `json:"timeout_ms"`
	CheckIntervalSeconds int       `json:"check_interval_seconds"`
	ExpectedStatusMin    int       `json:"expected_status_min"`
	ExpectedStatusMax    int       `json:"expected_status_max"`
	IsActive             bool      `json:"is_active"`
	NextCheckAt          time.Time `json:"next_check_at"`
	CreatedAt            time.Time `json:"created_at"`
	UpdatedAt            time.Time `json:"updated_at"`
}

type LatestStatus struct {
	Outcome    string    `json:"outcome"`
	StatusCode *int      `json:"status_code"`
	LatencyMS  *int64    `json:"latency_ms"`
	ErrorType  *string   `json:"error_type"`
	CheckedAt  time.Time `json:"checked_at"`
}

type ProbeBucket struct {
	BucketStart    time.Time `json:"bucket_start"`
	TotalChecks    int       `json:"total_checks"`
	UpChecks       int       `json:"up_checks"`
	DownChecks     int       `json:"down_checks"`
	ErrorChecks    int       `json:"error_checks"`
	UptimePercent  float64   `json:"uptime_percent"`
	AvgLatencyMS   *float64  `json:"avg_latency_ms"`
	LastStatusCode *int      `json:"last_status_code"`
	LastOutcome    *string   `json:"last_outcome"`
	LastCheckedAt  time.Time `json:"last_checked_at"`
}

type ProbeSummary struct {
	URL           MonitoredURL  `json:"url"`
	LatestStatus  *LatestStatus `json:"latest_status"`
	BucketMinutes int           `json:"bucket_minutes"`
	From          time.Time     `json:"from"`
	To            time.Time     `json:"to"`
	Buckets       []ProbeBucket `json:"buckets"`
}

type CreateCompanyInput struct {
	Name string `json:"name"`
	Slug string `json:"slug"`
}

type CreateURLInput struct {
	URL                  string `json:"url"`
	Method               string `json:"method"`
	TimeoutMS            int    `json:"timeout_ms"`
	CheckIntervalSeconds int    `json:"check_interval_seconds"`
	ExpectedStatusMin    int    `json:"expected_status_min"`
	ExpectedStatusMax    int    `json:"expected_status_max"`
}

func New(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) Ping(ctx context.Context) error {
	return s.db.PingContext(ctx)
}

func (s *Store) CreateCompany(ctx context.Context, input CreateCompanyInput) (Company, error) {
	now := time.Now().UTC()
	company := Company{
		ID:        uuid.NewString(),
		Name:      strings.TrimSpace(input.Name),
		Slug:      strings.TrimSpace(input.Slug),
		CreatedAt: now,
		UpdatedAt: now,
	}
	if company.Name == "" || company.Slug == "" {
		return Company{}, errors.New("name and slug are required")
	}

	err := s.db.QueryRowContext(ctx, `
		INSERT INTO companies (id, name, slug, created_at, updated_at)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, name, slug, created_at, updated_at
	`, company.ID, company.Name, company.Slug, company.CreatedAt, company.UpdatedAt).
		Scan(&company.ID, &company.Name, &company.Slug, &company.CreatedAt, &company.UpdatedAt)
	return company, err
}

func (s *Store) ListCompanies(ctx context.Context) ([]Company, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, name, slug, created_at, updated_at
		FROM companies
		ORDER BY created_at DESC
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var companies []Company
	for rows.Next() {
		var company Company
		if err := rows.Scan(&company.ID, &company.Name, &company.Slug, &company.CreatedAt, &company.UpdatedAt); err != nil {
			return nil, err
		}
		companies = append(companies, company)
	}
	return companies, rows.Err()
}

func (s *Store) CreateURL(ctx context.Context, companyID string, input CreateURLInput) (MonitoredURL, error) {
	normalized, err := NormalizeURL(input.URL)
	if err != nil {
		return MonitoredURL{}, err
	}
	if input.Method == "" {
		input.Method = "GET"
	}
	if input.TimeoutMS == 0 {
		input.TimeoutMS = 5000
	}
	if input.CheckIntervalSeconds == 0 {
		input.CheckIntervalSeconds = 60
	}
	if input.ExpectedStatusMin == 0 {
		input.ExpectedStatusMin = 200
	}
	if input.ExpectedStatusMax == 0 {
		input.ExpectedStatusMax = 399
	}

	now := time.Now().UTC()
	monitoredURL := MonitoredURL{
		ID:                   uuid.NewString(),
		CompanyID:            companyID,
		URL:                  strings.TrimSpace(input.URL),
		NormalizedURL:        normalized,
		Method:               strings.ToUpper(input.Method),
		TimeoutMS:            input.TimeoutMS,
		CheckIntervalSeconds: input.CheckIntervalSeconds,
		ExpectedStatusMin:    input.ExpectedStatusMin,
		ExpectedStatusMax:    input.ExpectedStatusMax,
		IsActive:             true,
		NextCheckAt:          now,
		CreatedAt:            now,
		UpdatedAt:            now,
	}

	err = s.db.QueryRowContext(ctx, `
		INSERT INTO monitored_urls (
			id, company_id, url, normalized_url, method, timeout_ms,
			check_interval_seconds, expected_status_min, expected_status_max,
			is_active, next_check_at, created_at, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
		RETURNING id, company_id, url, normalized_url, method, timeout_ms,
			check_interval_seconds, expected_status_min, expected_status_max,
			is_active, next_check_at, created_at, updated_at
	`, monitoredURL.ID, monitoredURL.CompanyID, monitoredURL.URL, monitoredURL.NormalizedURL,
		monitoredURL.Method, monitoredURL.TimeoutMS, monitoredURL.CheckIntervalSeconds,
		monitoredURL.ExpectedStatusMin, monitoredURL.ExpectedStatusMax, monitoredURL.IsActive,
		monitoredURL.NextCheckAt, monitoredURL.CreatedAt, monitoredURL.UpdatedAt).
		Scan(&monitoredURL.ID, &monitoredURL.CompanyID, &monitoredURL.URL, &monitoredURL.NormalizedURL,
			&monitoredURL.Method, &monitoredURL.TimeoutMS, &monitoredURL.CheckIntervalSeconds,
			&monitoredURL.ExpectedStatusMin, &monitoredURL.ExpectedStatusMax, &monitoredURL.IsActive,
			&monitoredURL.NextCheckAt, &monitoredURL.CreatedAt, &monitoredURL.UpdatedAt)
	return monitoredURL, err
}

func (s *Store) ListCompanyURLs(ctx context.Context, companyID string, search string) ([]MonitoredURL, error) {
	query := `
		SELECT id, company_id, url, normalized_url, method, timeout_ms,
			check_interval_seconds, expected_status_min, expected_status_max,
			is_active, next_check_at, created_at, updated_at
		FROM monitored_urls
		WHERE company_id = $1
	`
	args := []any{companyID}
	if strings.TrimSpace(search) != "" {
		query += ` AND normalized_url ILIKE $2`
		args = append(args, "%"+strings.ToLower(strings.TrimSpace(search))+"%")
	}
	query += ` ORDER BY created_at DESC`

	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	return scanURLs(rows)
}

func (s *Store) GetProbeSummary(ctx context.Context, urlID string, from time.Time, to time.Time, bucketMinutes int) (ProbeSummary, error) {
	if bucketMinutes <= 0 {
		bucketMinutes = 5
	}
	if to.IsZero() {
		to = time.Now().UTC()
	}
	if from.IsZero() || !from.Before(to) {
		from = to.Add(-24 * time.Hour)
	}

	var monitoredURL MonitoredURL
	err := s.db.QueryRowContext(ctx, `
		SELECT id, company_id, url, normalized_url, method, timeout_ms,
			check_interval_seconds, expected_status_min, expected_status_max,
			is_active, next_check_at, created_at, updated_at
		FROM monitored_urls
		WHERE id = $1
	`, urlID).Scan(&monitoredURL.ID, &monitoredURL.CompanyID, &monitoredURL.URL,
		&monitoredURL.NormalizedURL, &monitoredURL.Method, &monitoredURL.TimeoutMS,
		&monitoredURL.CheckIntervalSeconds, &monitoredURL.ExpectedStatusMin,
		&monitoredURL.ExpectedStatusMax, &monitoredURL.IsActive, &monitoredURL.NextCheckAt,
		&monitoredURL.CreatedAt, &monitoredURL.UpdatedAt)
	if err != nil {
		return ProbeSummary{}, err
	}

	summary := ProbeSummary{
		URL:           monitoredURL,
		BucketMinutes: bucketMinutes,
		From:          from,
		To:            to,
	}

	var latest LatestStatus
	err = s.db.QueryRowContext(ctx, `
		SELECT outcome, status_code, latency_ms, error_type, checked_at
		FROM url_latest_status
		WHERE url_id = $1
	`, urlID).Scan(&latest.Outcome, &latest.StatusCode, &latest.LatencyMS, &latest.ErrorType, &latest.CheckedAt)
	if err == nil {
		summary.LatestStatus = &latest
	} else if !errors.Is(err, sql.ErrNoRows) {
		return ProbeSummary{}, err
	}

	rows, err := s.db.QueryContext(ctx, `
		WITH bucketed AS (
			SELECT
				to_timestamp(floor(extract(epoch from checked_at) / ($4 * 60)) * ($4 * 60)) AT TIME ZONE 'UTC' AS bucket_start,
				outcome,
				status_code,
				latency_ms,
				checked_at
			FROM url_check_history
			WHERE url_id = $1 AND checked_at >= $2 AND checked_at <= $3
		),
		latest_in_bucket AS (
			SELECT DISTINCT ON (bucket_start)
				bucket_start,
				status_code AS last_status_code,
				outcome AS last_outcome,
				checked_at AS last_checked_at
			FROM bucketed
			ORDER BY bucket_start, checked_at DESC
		)
		SELECT
			b.bucket_start,
			count(*)::int AS total_checks,
			count(*) FILTER (WHERE b.outcome = 'up')::int AS up_checks,
			count(*) FILTER (WHERE b.outcome = 'down')::int AS down_checks,
			count(*) FILTER (WHERE b.outcome = 'error')::int AS error_checks,
			round((count(*) FILTER (WHERE b.outcome = 'up')::numeric / count(*)::numeric) * 100, 2)::float8 AS uptime_percent,
			avg(b.latency_ms)::float8 AS avg_latency_ms,
			l.last_status_code,
			l.last_outcome,
			l.last_checked_at
		FROM bucketed b
		JOIN latest_in_bucket l ON l.bucket_start = b.bucket_start
		GROUP BY b.bucket_start, l.last_status_code, l.last_outcome, l.last_checked_at
		ORDER BY b.bucket_start DESC
	`, urlID, from, to, bucketMinutes)
	if err != nil {
		return ProbeSummary{}, err
	}
	defer rows.Close()

	for rows.Next() {
		var bucket ProbeBucket
		if err := rows.Scan(&bucket.BucketStart, &bucket.TotalChecks, &bucket.UpChecks,
			&bucket.DownChecks, &bucket.ErrorChecks, &bucket.UptimePercent,
			&bucket.AvgLatencyMS, &bucket.LastStatusCode, &bucket.LastOutcome,
			&bucket.LastCheckedAt); err != nil {
			return ProbeSummary{}, err
		}
		summary.Buckets = append(summary.Buckets, bucket)
	}
	if err := rows.Err(); err != nil {
		return ProbeSummary{}, err
	}

	return summary, nil
}

func (s *Store) ClaimDueURLs(ctx context.Context, limit int, lease time.Duration) ([]MonitoredURL, error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback()

	rows, err := tx.QueryContext(ctx, `
		SELECT id, company_id, url, normalized_url, method, timeout_ms,
			check_interval_seconds, expected_status_min, expected_status_max,
			is_active, next_check_at, created_at, updated_at
		FROM monitored_urls
		WHERE is_active = true AND next_check_at <= now()
		ORDER BY next_check_at ASC
		LIMIT $1
		FOR UPDATE SKIP LOCKED
	`, limit)
	if err != nil {
		return nil, err
	}
	urls, err := scanURLs(rows)
	if err != nil {
		return nil, err
	}

	leaseSeconds := int(lease.Seconds())
	if leaseSeconds <= 0 {
		leaseSeconds = 30
	}

	for _, monitoredURL := range urls {
		_, err := tx.ExecContext(ctx, `
			UPDATE monitored_urls
			SET next_check_at = now() + ($2 * interval '1 second'), updated_at = now()
			WHERE id = $1
		`, monitoredURL.ID, leaseSeconds)
		if err != nil {
			return nil, err
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return urls, nil
}

func (s *Store) AdvanceURLSchedule(ctx context.Context, urlID string, intervalSeconds int) error {
	_, err := s.db.ExecContext(ctx, `
		UPDATE monitored_urls
		SET next_check_at = now() + ($2 * interval '1 second'), updated_at = now()
		WHERE id = $1
	`, urlID, intervalSeconds)
	return err
}

func (s *Store) WriteResult(ctx context.Context, result events.URLCheckResult) error {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{})
	if err != nil {
		return err
	}
	defer tx.Rollback()

	_, err = tx.ExecContext(ctx, `
		INSERT INTO url_check_history (
			check_id, company_id, url_id, outcome, status_code, latency_ms,
			error_type, error_message, checked_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (check_id) DO NOTHING
	`, result.CheckID, result.CompanyID, result.URLID, result.Outcome, result.StatusCode,
		result.LatencyMS, result.ErrorType, result.ErrorMessage, result.CheckedAt)
	if err != nil {
		return err
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO url_latest_status (
			url_id, company_id, last_check_id, outcome, status_code, latency_ms,
			error_type, checked_at, updated_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, now())
		ON CONFLICT (url_id) DO UPDATE SET
			company_id = EXCLUDED.company_id,
			last_check_id = EXCLUDED.last_check_id,
			outcome = EXCLUDED.outcome,
			status_code = EXCLUDED.status_code,
			latency_ms = EXCLUDED.latency_ms,
			error_type = EXCLUDED.error_type,
			checked_at = EXCLUDED.checked_at,
			updated_at = now()
		WHERE url_latest_status.checked_at <= EXCLUDED.checked_at
	`, result.URLID, result.CompanyID, result.CheckID, result.Outcome, result.StatusCode,
		result.LatencyMS, result.ErrorType, result.CheckedAt)
	if err != nil {
		return err
	}

	return tx.Commit()
}

func NormalizeURL(raw string) (string, error) {
	parsed, err := url.Parse(strings.TrimSpace(raw))
	if err != nil {
		return "", err
	}
	if parsed.Scheme == "" || parsed.Host == "" {
		return "", errors.New("url must include scheme and host")
	}
	parsed.Scheme = strings.ToLower(parsed.Scheme)
	parsed.Host = strings.ToLower(parsed.Host)
	return parsed.String(), nil
}

func scanURLs(rows *sql.Rows) ([]MonitoredURL, error) {
	defer rows.Close()

	var urls []MonitoredURL
	for rows.Next() {
		var monitoredURL MonitoredURL
		if err := rows.Scan(&monitoredURL.ID, &monitoredURL.CompanyID, &monitoredURL.URL,
			&monitoredURL.NormalizedURL, &monitoredURL.Method, &monitoredURL.TimeoutMS,
			&monitoredURL.CheckIntervalSeconds, &monitoredURL.ExpectedStatusMin,
			&monitoredURL.ExpectedStatusMax, &monitoredURL.IsActive, &monitoredURL.NextCheckAt,
			&monitoredURL.CreatedAt, &monitoredURL.UpdatedAt); err != nil {
			return nil, err
		}
		urls = append(urls, monitoredURL)
	}
	return urls, rows.Err()
}
