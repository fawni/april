FROM alpine:edge
WORKDIR /usr/src/april
COPY . .
RUN apk --no-cache add zig --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing
RUN zig build -Drelease

WORKDIR /app
RUN cp /usr/src/april/zig-out/bin/april /usr/src/april/config.json /app/
CMD [ "/app/april" ]
