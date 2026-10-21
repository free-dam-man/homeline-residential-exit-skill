#!/bin/sh
# usage: scan.sh CC  (env VPSIP, LIMIT) ; candidates in /scan/cand-CC-*.ovpn, login in /scan/auth.txt
# Run the container with --dns 8.8.8.8 (public resolver): cloud metadata DNS (e.g. 169.254.169.254) is
# unreachable once OpenVPN routes 0/1+128/1, which makes good nodes look dead (field case: GCP).
# Skips a node immediately on any known OpenVPN failure marker instead of waiting out the timeout
# (marker list idea adapted from vpnbox, MIT, https://github.com/sajadinmaker/vpnbox).
CC="$1"; LIMIT=${LIMIT:-5}; n=0
FAIL_RE='Options error|AUTH_FAILED|Cannot resolve host|Connection refused|Connection timed out|Connection reset by peer|No route to host|Network is unreachable|Error opening configuration file|Failed to establish|TUNSETIFF failed|All connections have been|Exiting due to fatal error'
for f in /scan/cand-"${CC}"-*.ovpn; do
  [ -f "$f" ] || continue; n=$((n+1)); [ "$n" -gt "$LIMIT" ] && break
  rm -f /tmp/o.log
  openvpn --config "$f" --auth-user-pass /scan/auth.txt --daemon --log /tmp/o.log
  ok=""; why="timeout"
  for _ in $(seq 1 22); do
    grep -q "Initialization Sequence Completed" /tmp/o.log 2>/dev/null && ok=1 && break
    m=$(grep -oE "$FAIL_RE" /tmp/o.log 2>/dev/null | head -1); [ -n "$m" ] && why="$m" && break
    sleep 1
  done
  if [ -n "$ok" ]; then
    out=$(curl -s -m 12 https://api.ipify.org)
    if [ -n "$out" ] && [ "$out" != "$VPSIP" ]; then
      c=$(curl -s -m 10 "http://ip-api.com/line/$out?fields=countryCode")
      if [ "$c" = "$CC" ]; then echo "WORKING $CC try=$n"; cp "$f" "/scan/working-${CC}.ovpn"; exit 0; fi
      echo "WRONGCC $CC try=$n got=$c"
    elif [ -z "$out" ] && curl -s -m 8 -o /dev/null https://1.1.1.1/cdn-cgi/trace; then
      echo "NODNS $CC try=$n (tunnel passes traffic by IP but DNS fails: start the container with --dns 8.8.8.8)"
    else echo "NOEXIT_OR_LEAK $CC try=$n"; fi
  else echo "FAIL $CC try=$n ($why)"; fi
  pkill openvpn 2>/dev/null; sleep 2
done
echo "NONE $CC tried=$n"; exit 1
