#!/bin/sh
# Route A gateway v2 (main path): OpenVPN client + microsocks + in-container kill switch + watchdog.
# Needs /vpn/client.ovpn and /vpn/auth.txt (VPN Gate public login: two lines "vpn" / "vpn").
# Kill switch: OUTPUT default DROP; allowed = loopback, tun+, replies to SOCKS clients, and the VPN remote only.
CFG=/vpn/client.ovpn
RIP=$(awk '$1=="remote"{print $2; exit}' "$CFG"); RPT=$(awk '$1=="remote"{print $3; exit}' "$CFG")
PROTO=$(awk '$1=="proto"{print $2; exit}' "$CFG"); case "$PROTO" in udp*) PROTO=udp;; *) PROTO=tcp;; esac
[ -f /vpn/auth.txt ] || { echo "missing /vpn/auth.txt (two lines: vpn / vpn)" >&2; exit 1; }
iptables -F OUTPUT; iptables -P OUTPUT DROP
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -o tun+ -j ACCEPT
iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -o eth0 -p "$PROTO" -d "$RIP" --dport "${RPT:-443}" -j ACCEPT
openvpn --config "$CFG" --auth-user-pass /vpn/auth.txt --daemon --log /tmp/ovpn.log
for _ in $(seq 1 30); do ip link show tun0 >/dev/null 2>&1 && break; sleep 1; done
ip link show tun0 >/dev/null 2>&1 || { echo "tun0 never came up" >&2; tail -5 /tmp/ovpn.log >&2; exit 1; }
microsocks -i 0.0.0.0 -p 1080 -u "$GATE_USER" -P "$GATE_PASS" &
MS=$!
t=0; bad=0
while sleep 20; do
  # pgrep, not a pidfile: OpenVPN deletes its pidfile on exit, so `kill -0 $(cat pidfile)` never fires (field bug 2026-10-21)
  pgrep -x openvpn >/dev/null || { echo "openvpn died" >&2; tail -3 /tmp/ovpn.log >&2; exit 2; }
  kill -0 "$MS" 2>/dev/null || exit 3
  t=$((t+1)); [ $((t % 3)) -eq 0 ] || continue
  # data-plane check through tun0 every ~60s; 3 misses in a row -> exit so Docker restarts (same node)
  if curl -s -o /dev/null -m 8 http://www.gstatic.com/generate_204; then bad=0; else bad=$((bad+1)); echo "dataplane miss $bad" >&2; fi
  [ "$bad" -ge 3 ] && { echo "tunnel stalled (tun up, no traffic) -> restart" >&2; exit 4; }
done
