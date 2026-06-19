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
