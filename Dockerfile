FROM alpine:edge
WORKDIR /usr/src/april
COPY . .
RUN apk --no-cache add zig --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing
RUN zig build -Drelease
RUN cp ./zig-out/bin/april config.json /app/

WORKDIR /app
CMD [ "/app/april" ]
