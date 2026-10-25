# Mihomo multi-country architecture / 多国 Mihomo 热备架构

Placeholders only. Replace `<…>` on your own host. No real IPs, UUIDs, or certs belong in git.

## Goal

Run **five independent country lines** (JP / HK / KR / GB / US) on one self-hosted box, with:

1. A **sticky Docker SOCKS** primary per country (OpenVPN inside a gateway container → authenticated SOCKS on loopback).  
2. A **Mihomo userspace OpenVPN hot-standby pool** per country (several volunteer endpoints; health-checked).  
3. A **fallback group** that prefers the sticky Docker line, then the pool.  
4. Optional **CDN DIRECT offload** so big static hosts skip the residential tunnel.

Client-facing ingress stays whatever you already use (standalone Xray VLESS+Reality per country, or a single Mihomo listener with per-user country routing). This doc focuses on the **egress side**.

## Topology (text)

```text
Client
  │  VLESS+Reality (or WS) — one inbound per country / per UUID
  ▼
Ingress (Xray or Mihomo listener)
  │  dials 127.0.0.1:<COUNTRY_SOCKS_OR_GROUP>
  ▼
Per-country FALLBACK group  (example name: JP-LINE)
  ├─ 1) sticky Docker SOCKS   name: JP-DOCKER-STICKY
  │      → gateway container OpenVPN → volunteer residential node
  │      → microsocks on 127.0.0.1 only
  └─ 2) Mihomo OVPN pool      name: JP-OVPN-POOL  (url-test or fallback)
         → type: openvpn proxies JP-OVPN-A / JP-OVPN-B / …
         → userspace, no /dev/net/tun required for *this* pool path

Optional rule layer:
  DOMAIN-SUFFIX,googlevideo.com,DIRECT   # CDN offload example
  DOMAIN-SUFFIX,akamai.net,DIRECT
  MATCH,<COUNTRY>-LINE
```

Same pattern for `HK-LINE`, `KR-LINE`, `GB-LINE`, `US-LINE`. Do **not** share one SOCKS port or one OpenVPN process across countries: a bad UK pool must not take down JP.

## Why “sticky Docker” + “OVPN pool”

| Layer | Role | Failure mode |
|---|---|---|
| Docker sticky | Keeps one working residential exit warm; client link (UUID/port/Reality) never changes when you only rotate `client.ovpn` inside the gateway | Tunnel dies → SOCKS fails → fallback fires |
| Mihomo OVPN pool | Several pre-declared volunteer endpoints; `url-test` / `fallback` picks a live one without waiting for a full Docker rescan | Pool `cc` label may lie → **must** pair with [post-connect geo gate](post-connect-geo-gate.md) |
| Fallback group | Prefer sticky; if sticky is down, use pool; if both down, fail closed (no VPS IP leak) | Mis-ordered group = “works” but exits the wrong country |

## Sticky Docker SOCKS (per country)

Reuse the v1 Route A idea from the parent skill:

- One gateway container per country (`NET_ADMIN` + `/dev/net/tun` on the VPS path).  
- Kill switch: container `OUTPUT` default DROP; only `lo` / `tun+` / VPN peer.  
- Publish SOCKS **only** on `127.0.0.1:<PORT>` with fresh credentials.  
- Manager / heal script may replace `client.ovpn` and restart **that** gateway only.

Mihomo (or Xray) then points a `socks` outbound at that loopback port:

```yaml
# illustrative — fake names / ports
- name: JP-DOCKER-STICKY
  type: socks
  server: 127.0.0.1
  port: 11081          # your JP gateway host port
  username: <GATE_USER>
  password: <GATE_PASS>
```

## Mihomo OpenVPN hot-standby pool

Mihomo (`Clash.Meta`) can speak `type: openvpn` in userspace on builds that include it. Volunteer SoftEther/VPN Gate nodes often share a common CA pattern; you still **must** obtain current endpoints from a list you trust and **verify country after connect**.

Sketch (all values fake):

```yaml
proxies:
  - name: JP-OVPN-A
    type: openvpn
    server: 203.0.113.10      # docs IP — replace
    port: 1194
    # cipher / auth / ca / cert / key: follow your verified template
    # never commit real key material

  - name: JP-OVPN-B
    type: openvpn
    server: 203.0.113.11
    port: 443

proxy-groups:
  - name: JP-OVPN-POOL
    type: url-test
    proxies: [JP-OVPN-A, JP-OVPN-B]
    url: http://www.gstatic.com/generate_204
    interval: 120
    tolerance: 50

  - name: JP-LINE
    type: fallback
    proxies: [JP-DOCKER-STICKY, JP-OVPN-POOL]
    url: http://www.gstatic.com/generate_204
    interval: 60
```

Repeat groups for HK / KR / GB / US with **disjoint** proxy name sets.

## Optional CDN DIRECT offload

Residential tunnels are scarce and slow. If the operator agrees, send known CDN / static domains via `DIRECT` (VPS egress) while keeping account-sensitive sites on the residential line:

```yaml
rules:
  - DOMAIN-SUFFIX,googlevideo.com,DIRECT
  - DOMAIN-SUFFIX,ytimg.com,DIRECT
  - DOMAIN-SUFFIX,akamai.net,DIRECT
  - DOMAIN-SUFFIX,cloudfront.net,DIRECT
  # … operator-curated list …
  - MATCH,JP-LINE
```

Trade-off: CDN offload means **those** domains see the VPS IP (often datacenter). Document that honestly. Default for a “pure residential” build: **no** CDN offload.

## DNS note

Inside Mihomo, prefer DNS that does not collapse when the tunnel takes the default route, e.g. DoH/DoT tagged to a non-tunnel dialer, or `tcp://8.8.8.8:53` via a known-good path. Cloud metadata DNS (`169.254.169.254`) will black-hole you after redirect-gateway — same lesson as the v1 Docker skill.

## Memory / process hygiene

- Docker scans: **one at a time**, memory-capped (see parent `scan.sh.example`).  
- Do not run five simultaneous full rescans on a 512MB box.  
- Mihomo OVPN pool size: start with 2–5 endpoints per country; more = more idle handshakes.

## What to measure before calling a line “up”

For each country line, through the **client path** (not only VPS curl):

| Check | Pass look |
|---|---|
| Exit IP ≠ VPS IP | kill switch / no leak |
| `countryCode` == target (`JP`/`HK`/`KR`/`GB`/`US`) | geo gate |
| Hosting / residential flag (best-effort) | not “call it 家宽” if hosting=true |
| Sticky down → pool up | fallback works |
| Pool endpoint with lying `cc` | rejected + blacklisted |

See [post-connect-geo-gate.md](post-connect-geo-gate.md).

## Honest limits

- Volunteer nodes die, move, or mis-label country.  
- Userspace OpenVPN support depends on your Mihomo build; pin a version and re-test after upgrades.  
- Five countries on one small VPS is feasible but not free: RAM, file descriptors, and UDP/TCP churn add up.  
- This architecture does **not** turn your VPS into a commercial multi-tenant airport.
