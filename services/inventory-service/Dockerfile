FROM golang:1.24-alpine AS build
WORKDIR /app
ENV GONOSUMDB=* GOFLAGS=-mod=mod
RUN apk add --no-cache git
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o inventory-service .

FROM alpine:3.21
WORKDIR /app
COPY --from=build /app/inventory-service .
CMD ["./inventory-service"]
