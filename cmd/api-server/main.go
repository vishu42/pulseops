package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"
	"strings"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/vishu42/pulseops/internal/config"
	"github.com/vishu42/pulseops/internal/store"
	"github.com/vishu42/pulseops/internal/ui"
)

type server struct {
	store *store.Store
}

func main() {
	cfg := config.Load()

	db, err := sql.Open("pgx", cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	s := &server{store: store.New(db)}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("GET /api/v1/companies", s.listCompanies)
	mux.HandleFunc("POST /api/v1/companies", s.createCompany)
	mux.HandleFunc("GET /api/v1/companies/{company_id}/urls", s.listCompanyURLs)
	mux.HandleFunc("POST /api/v1/companies/{company_id}/urls", s.createCompanyURL)
	mux.HandleFunc("GET /api/v1/urls/{url_id}/probe-summary", s.getProbeSummary)
	mux.Handle("GET /", http.FileServerFS(ui.Files()))

	httpServer := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           logging(mux),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("api-server listening on %s", cfg.HTTPAddr)
	log.Fatal(httpServer.ListenAndServe())
}

func (s *server) health(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
	defer cancel()
	if err := s.store.Ping(ctx); err != nil {
		writeError(w, http.StatusServiceUnavailable, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *server) createCompany(w http.ResponseWriter, r *http.Request) {
	var input store.CreateCompanyInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	company, err := s.store.CreateCompany(r.Context(), input)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, company)
}

func (s *server) listCompanies(w http.ResponseWriter, r *http.Request) {
	companies, err := s.store.ListCompanies(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"companies": companies})
}

func (s *server) createCompanyURL(w http.ResponseWriter, r *http.Request) {
	companyID := r.PathValue("company_id")
	if strings.TrimSpace(companyID) == "" {
		writeError(w, http.StatusBadRequest, errors.New("company_id is required"))
		return
	}

	var input store.CreateURLInput
	if err := json.NewDecoder(r.Body).Decode(&input); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	monitoredURL, err := s.store.CreateURL(r.Context(), companyID, input)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, monitoredURL)
}

func (s *server) listCompanyURLs(w http.ResponseWriter, r *http.Request) {
	urls, err := s.store.ListCompanyURLs(r.Context(), r.PathValue("company_id"), r.URL.Query().Get("q"))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"urls": urls})
}

func (s *server) getProbeSummary(w http.ResponseWriter, r *http.Request) {
	hours := queryInt(r, "hours", 24)
	if hours < 1 {
		hours = 1
	}
	if hours > 24*60 {
		hours = 24 * 60
	}

	bucketMinutes := queryInt(r, "bucket_minutes", 5)
	if bucketMinutes < 1 {
		bucketMinutes = 5
	}
	if bucketMinutes > 60 {
		bucketMinutes = 60
	}

	to := time.Now().UTC()
	from := to.Add(-time.Duration(hours) * time.Hour)
	summary, err := s.store.GetProbeSummary(r.Context(), r.PathValue("url_id"), from, to, bucketMinutes)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("url not found"))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, summary)
}

func queryInt(r *http.Request, key string, fallback int) int {
	value := r.URL.Query().Get(key)
	if value == "" {
		return fallback
	}
	parsed, err := strconv.Atoi(value)
	if err != nil {
		return fallback
	}
	return parsed
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("write response: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]string{"error": err.Error()})
}

func logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}
