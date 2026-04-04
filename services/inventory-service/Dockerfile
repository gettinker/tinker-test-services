FROM golang:1.22-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o inventory-service .

FROM alpine:3.19
WORKDIR /app
COPY --from=build /app/inventory-service .
CMD ["./inventory-service"]
