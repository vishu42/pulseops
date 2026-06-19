package kafkaio

import (
	"context"
	"encoding/json"
	"time"

	"github.com/segmentio/kafka-go"
)

type Producer struct {
	writer *kafka.Writer
}

func NewProducer(brokers []string, topic string) *Producer {
	return &Producer{
		writer: &kafka.Writer{
			Addr:         kafka.TCP(brokers...),
			Topic:        topic,
			Balancer:     &kafka.Hash{},
			RequiredAcks: kafka.RequireAll,
			Async:        false,
		},
	}
}

func (p *Producer) PublishJSON(ctx context.Context, key string, value any, headers map[string]string) error {
	body, err := json.Marshal(value)
	if err != nil {
		return err
	}

	messageHeaders := make([]kafka.Header, 0, len(headers))
	for k, v := range headers {
		messageHeaders = append(messageHeaders, kafka.Header{Key: k, Value: []byte(v)})
	}

	return p.writer.WriteMessages(ctx, kafka.Message{
		Key:     []byte(key),
		Value:   body,
		Time:    time.Now().UTC(),
		Headers: messageHeaders,
	})
}

func (p *Producer) Close() error {
	return p.writer.Close()
}

func NewReader(brokers []string, topic string, groupID string) *kafka.Reader {
	return kafka.NewReader(kafka.ReaderConfig{
		Brokers:        brokers,
		Topic:          topic,
		GroupID:        groupID,
		MinBytes:       1,
		MaxBytes:       10e6,
		CommitInterval: time.Second,
	})
}
