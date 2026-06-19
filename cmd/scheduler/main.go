package main

import (
	"context"
	"database/sql"
	"log"
	"time"

	"github.com/google/uuid"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/vishu42/pulseops/internal/config"
	"github.com/vishu42/pulseops/internal/events"
	"github.com/vishu42/pulseops/internal/kafkaio"
	"github.com/vishu42/pulseops/internal/store"
)

func main() {
	cfg := config.Load()

	db, err := sql.Open("pgx", cfg.DatabaseURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	st := store.New(db)
	producer := kafkaio.NewProducer(cfg.KafkaBrokers, cfg.CheckJobsTopic)
	defer producer.Close()

	ticker := time.NewTicker(cfg.SchedulerTick)
	defer ticker.Stop()

	log.Printf("scheduler started batch=%d tick=%s", cfg.SchedulerBatch, cfg.SchedulerTick)
	for {
		if err := enqueueDue(context.Background(), st, producer, cfg.SchedulerBatch); err != nil {
			log.Printf("scheduler tick failed: %v", err)
		}
		<-ticker.C
	}
}

func enqueueDue(ctx context.Context, st *store.Store, producer *kafkaio.Producer, batch int) error {
	urls, err := st.ClaimDueURLs(ctx, batch, 30*time.Second)
	if err != nil {
		return err
	}
	for _, monitoredURL := range urls {
		job := events.URLCheckJob{
			CheckID:           uuid.NewString(),
			CompanyID:         monitoredURL.CompanyID,
			URLID:             monitoredURL.ID,
			URL:               monitoredURL.URL,
			Method:            monitoredURL.Method,
			TimeoutMS:         monitoredURL.TimeoutMS,
			ExpectedStatusMin: monitoredURL.ExpectedStatusMin,
			ExpectedStatusMax: monitoredURL.ExpectedStatusMax,
			ScheduledAt:       time.Now().UTC(),
			Attempt:           1,
		}
		if err := producer.PublishJSON(ctx, monitoredURL.ID, job, map[string]string{
			"event_type":     "url_check_job",
			"schema_version": "1",
			"trace_id":       job.CheckID,
		}); err != nil {
			return err
		}
		if err := st.AdvanceURLSchedule(ctx, monitoredURL.ID, monitoredURL.CheckIntervalSeconds); err != nil {
			return err
		}
		log.Printf("enqueued check_id=%s url_id=%s", job.CheckID, job.URLID)
	}
	return nil
}
