# Multi-stage Dockerfile — проект go (статический бинарник, кэш GOMODCACHE).
FROM golang:1.24-bookworm AS builder
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/server .

FROM scratch
COPY --from=builder /out/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]