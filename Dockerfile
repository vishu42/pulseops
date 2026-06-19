FROM golang:1.23-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG SERVICE=api-server
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/pulseops ./cmd/${SERVICE}

FROM alpine:3.21

RUN addgroup -S pulseops && adduser -S pulseops -G pulseops

WORKDIR /app
COPY --from=build /out/pulseops /app/pulseops

USER pulseops
EXPOSE 8081

ENTRYPOINT ["/app/pulseops"]

