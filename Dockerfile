FROM alpine:edge AS builder
WORKDIR /usr/src/april
COPY . .
RUN apk --no-cache add zig --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing
RUN zig build -Drelease

FROM alpine:edge
WORKDIR /app
COPY --from=builder /usr/src/april/zig-out/bin/april /usr/src/april/config.json /app/
CMD [ "/app/april" ]
