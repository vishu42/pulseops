package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"log"

	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/segmentio/kafka-go"
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
	reader := kafkaio.NewReader(cfg.KafkaBrokers, cfg.CheckResultsTopic, cfg.ConsumerGroup+"-status-writer")
	defer reader.Close()

	log.Printf("status-writer started")
	for {
		message, err := reader.FetchMessage(context.Background())
		if err != nil {
			log.Printf("fetch result: %v", err)
			continue
		}

		var result events.URLCheckResult
		if err := json.Unmarshal(message.Value, &result); err != nil {
			log.Printf("decode result offset=%d: %v", message.Offset, err)
			commit(reader, message)
			continue
		}

		if err := st.WriteResult(context.Background(), result); err != nil {
			log.Printf("write result check_id=%s: %v", result.CheckID, err)
			continue
		}

		commit(reader, message)
		log.Printf("wrote result check_id=%s url_id=%s outcome=%s", result.CheckID, result.URLID, result.Outcome)
	}
}

func commit(reader *kafka.Reader, message kafka.Message) {
	if err := reader.CommitMessages(context.Background(), message); err != nil {
		log.Printf("commit offset=%d: %v", message.Offset, err)
	}
}
