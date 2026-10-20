FROM alpine:3.20 AS builder
RUN apk add --no-cache build-base git && git clone --depth 1 https://github.com/rofl0r/microsocks /tmp/microsocks && make -C /tmp/microsocks
FROM alpine:3.20
COPY --from=builder /tmp/microsocks/microsocks /usr/local/bin/microsocks
RUN apk add --no-cache openvpn curl iptables
COPY entrypoint.sh /entrypoint.sh
COPY scan.sh /scan.sh
RUN chmod +x /entrypoint.sh /scan.sh
ENTRYPOINT ["/entrypoint.sh"]
