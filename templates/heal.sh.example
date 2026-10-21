#!/bin/bash
# OPTIONAL patrol/self-heal (node swap). The gateway's own minute check already restarts stalled tunnels;
# this script additionally replaces a dead node. usage: heal.sh CC CONTAINER LINE_DIR SOCKS_PORT
# Parameters via env (defaults shown): HOMELINE_BASE=/opt/homeline  GATEWAY_IMAGE=homeline-gw:v2
#   VPS_IP=<auto: curl ipify direct>  GATEWAY_DNS=8.8.8.8  SCAN_MAX=5  FAIL_BEFORE_SCAN=2
# LINE_DIR must contain .env, ovpn/client.ovpn, ovpn/auth.txt. HOMELINE_BASE must contain fetch.py.
# Only the OpenVPN node is swapped; Xray UUID/port/Reality keys/link are never touched.
set -u
CC=$1; CONT=$2; DIR=$3; SPORT=$4; low=$(echo "$CC" | tr '[:upper:]' '[:lower:]')
BASE=${HOMELINE_BASE:-/opt/homeline}; IMAGE=${GATEWAY_IMAGE:-homeline-gw:v2}
H=$BASE/heal; W=$H/work-$low; mkdir -p "$W"
ST=$H/$low.status.json; LOG=$H/$low.log; CNT=$H/$low.count
SCAN_MAX=${SCAN_MAX:-5}; FAIL_BEFORE_SCAN=${FAIL_BEFORE_SCAN:-2}
log(){ echo "$(date -Is) [$CC] $*" >> "$LOG"; tail -n 300 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; }
st(){ printf '{"cc":"%s","checked_at":"%s","ok":%s,"consecutive_failures":%s,"note":"%s"}\n' "$CC" "$(date -Is)" "$1" "$2" "$3" > "$ST"; }
VPSIP=${VPS_IP:-$(curl -s -m 10 https://api.ipify.org)}
PR=""
probe(){
  # shellcheck disable=SC1091
  . "$DIR/.env"
  local ip c
  ip=$(curl -s -m 15 --socks5-hostname "127.0.0.1:$SPORT" --proxy-user "$GATE_USER:$GATE_PASS" https://api.ipify.org 2>/dev/null)
  [ -z "$ip" ] && { PR="no_exit"; return 1; }
  [ -n "$VPSIP" ] && [ "$ip" = "$VPSIP" ] && { PR="LEAK_vps_ip"; return 1; }
  c=$(curl -s -m 12 "http://ip-api.com/line/$ip?fields=countryCode" 2>/dev/null)
  [ "$c" = "$CC" ] || { PR="country_mismatch_$c"; return 1; }
  PR=ok; return 0
}
if probe; then echo 0 > "$CNT"; st true 0 ok; log "probe ok"; exit 0; fi
N=$(( $(cat "$CNT" 2>/dev/null || echo 0) + 1 )); echo "$N" > "$CNT"
st false "$N" "$PR"; log "probe FAIL ($PR) count=$N"
if [ "$N" -lt "$FAIL_BEFORE_SCAN" ] && [ "$PR" = "no_exit" ]; then
  docker restart "$CONT" >/dev/null 2>&1; log "restarted gateway (same node)"; exit 0
fi
exec 9>/run/homeline-heal.lock
flock -w 200 9 || { log "another scan running, skip"; exit 0; }
cp "$DIR/ovpn/auth.txt" "$W/auth.txt"; chmod 600 "$W/auth.txt"
log "rescan: $(python3 "$BASE/fetch.py" "$CC" "$W" "$SCAN_MAX" "$DIR/ovpn/client.ovpn" 2>&1 | tail -1)"
rm -f "$W/working-$CC.ovpn"
docker run --rm --dns "${GATEWAY_DNS:-8.8.8.8}" --memory 48m --cap-add=NET_ADMIN --device=/dev/net/tun -e VPSIP="$VPSIP" -e LIMIT="$SCAN_MAX" \
  -v "$W":/scan --entrypoint sh "$IMAGE" /scan.sh "$CC" 2>&1 | tail -n $((SCAN_MAX+1)) >> "$LOG"
if [ -f "$W/working-$CC.ovpn" ]; then
  cat "$W/working-$CC.ovpn" > "$DIR/ovpn/client.ovpn"; chmod 600 "$DIR/ovpn/client.ovpn"
  docker restart "$CONT" >/dev/null; sleep 20
  if probe; then echo 0 > "$CNT"; st true 0 healed_new_node; log "healed with new node"; exit 0; fi
  log "new node probe failed ($PR)"
fi
rm -f "$W"/cand-*.ovpn
log "heal failed this round"
