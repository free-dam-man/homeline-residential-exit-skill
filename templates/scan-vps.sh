#!/bin/bash
# scan-vps.sh — READ-ONLY pre-flight scan for the homeline skill (Phase 0).
# Installs nothing, writes nothing outside stdout, changes no config/service/firewall.
# Run as root (or with sudo) for complete port/process/firewall info; non-root works with gaps.
# Usage: bash scan-vps.sh            (plain report)
# Every line is "key: value" inside [sections] so an AI can parse it.
set -u
LC_ALL=C; export LC_ALL
has(){ command -v "$1" >/dev/null 2>&1; }
sec(){ printf '\n[%s]\n' "$1"; }
kv(){ printf '%s: %s\n' "$1" "${2:-unknown}"; }
T(){ timeout "$@"; }

sec system
if [ -r /etc/os-release ]; then
  # shellcheck disable=SC1091
  . /etc/os-release; kv distro "${ID:-?}"; kv version "${VERSION_ID:-?}"; kv pretty "${PRETTY_NAME:-?}"
else kv distro unknown; fi
kv kernel "$(uname -r)"
ARCH=$(uname -m); kv arch "$ARCH"
case "$ARCH" in x86_64|amd64) kv xray_asset Xray-linux-64.zip;; aarch64|arm64) kv xray_asset Xray-linux-arm64-v8a.zip;; *) kv xray_asset "UNSUPPORTED($ARCH)";; esac
kv init "$(ps -p 1 -o comm= 2>/dev/null)"
kv user "$(id -un) uid=$(id -u)"
if [ "$(id -u)" -eq 0 ]; then kv privilege root; elif has sudo && sudo -n true 2>/dev/null; then kv privilege sudo-nopasswd; else kv privilege "limited (re-run as root for full report)"; fi

sec resources
kv cpu_count "$(nproc 2>/dev/null)"
kv cpu_model "$(awk -F: '/model name|^Model/{gsub(/^ +/,"",$2);print $2;exit}' /proc/cpuinfo 2>/dev/null)"
MEM=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo); AV=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
SW=$(awk '/SwapTotal/{print int($2/1024)}' /proc/meminfo)
kv mem_total_mb "$MEM"; kv mem_available_mb "$AV"; kv swap_total_mb "$SW"
kv disk_root "$(df -Pm / | awk 'NR==2{print "size_mb="$2" free_mb="$4" used="$5}')"
if [ "${MEM:-0}" -lt 1024 ] && [ "${SW:-0}" -lt 512 ]; then kv memory_verdict "LOW: <1GB RAM and little swap -> propose a 1GB swap file before building"; else kv memory_verdict ok; fi

sec virtualization
V=unknown
if has systemd-detect-virt; then V=$(systemd-detect-virt 2>/dev/null || true); fi
[ -e /proc/vz ] && [ ! -e /proc/bc ] && V="openvz"
grep -qa container=lxc /proc/1/environ 2>/dev/null && V="lxc"
kv virt "${V:-none}"
if [ -c /dev/net/tun ]; then
  if (exec 3<>/dev/net/tun) 2>/dev/null; then kv tun "present+openable"; else kv tun "present (open not permitted for this user)"; fi
else kv tun "MISSING -> gateway route impossible unless provider enables TUN"; fi
kv iptables_bin "$(has iptables && iptables --version 2>/dev/null | head -1 || echo absent)"

sec network
kv ipv4_public "$(T 8 curl -4 -s https://api.ipify.org 2>/dev/null || echo none)"
kv ipv6_public "$(T 8 curl -6 -s https://api64.ipify.org 2>/dev/null || echo none)"
kv default_iface "$(ip route show default 2>/dev/null | awk '{print $5;exit}')"
INFO=$(T 10 curl -s "http://ip-api.com/line?fields=countryCode,isp,org,as,hosting" 2>/dev/null | tr '\n' '|')
kv vps_ip_info "${INFO:-lookup failed} (countryCode|isp|org|as|hosting)"
C=$(T 25 curl -s -o /dev/null -w '%{http_code}' https://www.vpngate.net/api/iphone/ 2>/dev/null)
kv vpngate_api "http=${C:-000}"
if has nc; then
  if T 6 nc -u -z -w3 1.1.1.1 53 2>/dev/null; then kv outbound_udp "probe sent (nc -u ok; not a delivery proof)"; else kv outbound_udp "nc -u failed"; fi
elif has dig; then
  if T 6 dig +time=3 +tries=1 @1.1.1.1 example.com >/dev/null 2>&1; then kv outbound_udp "ok (dns to 1.1.1.1)"; else kv outbound_udp "blocked?"; fi
else
  if T 6 bash -c 'exec 3<>/dev/udp/1.1.1.1/53' 2>/dev/null; then kv outbound_udp "socket ok (unverified reply)"; else kv outbound_udp unknown; fi
fi

sec listening_ports
if has ss; then ss -Hlntup 2>/dev/null | awk '{p=$7; sub(/users:\(\("/,"",p); sub(/".*/,"",p); print $1" "$5" "p}' | sort -u
else echo "ss missing"; fi

sec docker
if has docker; then
  kv docker_version "$(docker --version 2>/dev/null)"
  kv compose "$(docker compose version 2>/dev/null || echo absent)"
  kv daemon "$(systemctl is-active docker 2>/dev/null || echo unknown)"
  echo "containers:"; docker ps -a --format '  {{.Names}} | {{.Image}} | {{.Status}} | {{.Ports}}' 2>/dev/null
else kv docker_version "absent (install only with operator consent)"; fi

sec services_running
if has systemctl; then systemctl list-units --type=service --state=running --no-legend --plain 2>/dev/null | awk '{print "  "$1}'; fi

sec existing_proxies_panels
PAT='x-ui|3x-ui|xray|v2ray|sing-box|hysteria|tuic|naive|trojan|shadowsocks|ss-server|ssserver|marzban|hiddify|s-ui|nginx|caddy|haproxy|openvpn|wireguard|wg-quick|gost|brook|frp'
FOUND=0
for src in "$(ps -eo comm= 2>/dev/null)" "$(systemctl list-unit-files --no-legend 2>/dev/null | awk '{print $1}')" "$(has docker && docker ps -a --format '{{.Names}} {{.Image}}' 2>/dev/null)"; do
  m=$(printf '%s\n' "$src" | grep -Eio "$PAT" | sort -u | tr '\n' ' ')
  [ -n "$m" ] && { echo "  detected: $m"; FOUND=1; }
done
for d in /usr/local/x-ui /etc/x-ui /opt/marzban /etc/sing-box /usr/local/etc/xray /etc/hysteria /etc/nginx /etc/caddy; do [ -e "$d" ] && echo "  path: $d"; done
[ "$FOUND" -eq 0 ] && echo "  none detected by name (still treat every listening port as taken)"

sec firewall
if has ufw; then echo "ufw:"; ufw status 2>/dev/null | sed 's/^/  /'; fi
if has firewall-cmd; then echo "firewalld: $(firewall-cmd --state 2>/dev/null)"; firewall-cmd --list-all 2>/dev/null | sed 's/^/  /'; fi
if has nft; then echo "nft tables:"; nft list tables 2>/dev/null | sed 's/^/  /'; fi
if has iptables; then echo "iptables INPUT policy+rules:"; iptables -S INPUT 2>/dev/null | head -40 | sed 's/^/  /'; fi
echo "note: cloud security group / provider firewall is NOT visible from inside the VPS"

sec end
kv scan_mode "read-only; nothing installed or changed"
