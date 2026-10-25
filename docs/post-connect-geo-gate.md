# Post-connect geo gate / 连上后验国家

Pool metadata lies. Treat `CountryShort`, CSV `cc=UK`, and friendly node names as **hints**, never as proof.

## Why this exists (worked example)

A production UK line once preferred a Docker sticky primary that had dialed a volunteer endpoint advertised as `cc=UK` / residential / low fraud. After connect, the real exit was:

- Country: **Ukraine (UA)**  
- City: **Kyiv**  
- ASN / ISP: a Corbina-class telecom in UA  
- Geo lookup also flagged proxy-like attributes on some APIs  

Clients still showed a British-looking **label** because the inbound name and old patrol snapshot were not updated. The pool did not “become British” — the selector trusted a wrong `cc`.

**Rule:** after the tunnel/SOCKS is up, measure exit geography **through that SOCKS**. If `countryCode ≠ target`, reject the node, blacklist it, rotate.

## Probe pattern (SOCKS → ip-api)

Replace placeholders. Do not log full production exit IPs into public docs.

```bash
# TARGET_CC: JP | HK | KR | GB | US   (VPN Gate often uses GB for UK)
TARGET_CC=GB
SOCKS=127.0.0.1:11086          # loopback SOCKS for that country line
USER=<GATE_USER>
PASS=<GATE_PASS>

# 1) learn exit IP via the tunnel
EXIT_IP=$(curl -sS -m 15 \
  --socks5-hostname "${USER}:${PASS}@${SOCKS}" \
  https://api.ipify.org)

# 2) ask a geo API *through the same SOCKS* (avoids “lookup from VPS egress” lies)
#    fields keep the response small; adjust provider if ip-api is rate-limited
GEO=$(curl -sS -m 15 \
  --socks5-hostname "${USER}:${PASS}@${SOCKS}" \
  "http://ip-api.com/json/${EXIT_IP}?fields=status,country,countryCode,city,isp,as,proxy,hosting")

echo "$GEO"
# expect: "countryCode":"GB" (or JP/HK/KR/US for those lines)

CODE=$(printf '%s' "$GEO" | sed -n 's/.*"countryCode":"\([A-Z]*\)".*/\1/p')
if [ "$CODE" != "$TARGET_CC" ]; then
  echo "GEO_GATE_REJECT measured=$CODE want=$TARGET_CC"
  exit 42
fi
```

Notes:

- Prefer `--socks5-hostname` so DNS also goes through the tunnel.  
- Compare against **ISO codes you actually store** (`UK` in UI → normalize to `GB` everywhere in scripts).  
- Optional extra rejects: `hosting=true`, known SoftEther operator space, empty city, or `proxy=true` if your threat model cares.  
- On reject: do **not** leave clients on that exit; fail the health check so fallback/heal runs.

## Blacklist

Keep a small JSON/text set keyed by volunteer endpoint identity (`ip:port` or stable host id), not by the lying `cc` string.

```text
# pseudocode state file — example shape only
{
  "203.0.113.50:5555": { "until": 1730000000, "reason": "geo_mismatch want=GB got=UA" },
  "203.0.113.51:1194": { "until": 1730000000, "reason": "geo_mismatch want=GB got=DE" }
}
```

Suggested policy:

1. On geo mismatch → add endpoint with TTL (e.g. 1–24h).  
2. Candidate fetch **skips** blacklisted endpoints.  
3. SoftEther / known non-residential ranges stay excluded by default (parent skill already documents JP SoftEther traps).  
4. Never “fix” a wrong-country exit as the requested country in client remarks.

## Where to hook it

| Layer | Hook |
|---|---|
| Docker gateway heal / rotate | After rewrite `client.ovpn` + restart, run the SOCKS geo probe before clearing failure counters |
| Mihomo OVPN pool | After a proxy becomes active (or on a timer), probe via that proxy; if wrong country, mark unhealthy / remove from group and blacklist the server |
| Status JSON | Record `requested_cc`, `measured_cc`, `measured_city`, `geo_gate=pass|reject` — use placeholders in public examples |

## UK-only patch pattern for `vpngate.py` (pseudocode)

Apply the same idea to any country; UK/GB is called out because lying `cc=UK` was observed in the wild.

```python
# pseudocode — do not paste production secrets; wire into your manager's rotate()

TARGET = os.environ.get("TARGET_CC", "GB")  # UK UI → GB
BL_PATH = "/state/blacklist.json"
BL_SECONDS = int(os.environ.get("BL_SECONDS", "3600"))

def normalize_cc(cc: str) -> str:
    cc = (cc or "").strip().upper()
    return "GB" if cc == "UK" else cc

def socks_geo(socks_host, socks_port, user, password) -> dict:
    """Return {ip, countryCode, city, isp, ...} measured THROUGH the SOCKS."""
    # 1) GET https://api.ipify.org via socks5h
    # 2) GET http://ip-api.com/json/<ip>?fields=... via socks5h
    # raise on timeout / non-200 / status != success
    ...

def blacklist_add(endpoint: str, reason: str) -> None:
    # endpoint like "203.0.113.50:5555"
    # persist BL_PATH with unix expiry now+BL_SECONDS
    ...

def blacklist_hit(endpoint: str) -> bool:
    ...

def pick_candidate(rows):
    for row in rows:
        endpoint = f"{row['ip']}:{row['port']}"
        if blacklist_hit(endpoint):
            continue
        claimed = normalize_cc(row.get("CountryShort") or row.get("cc"))
        if claimed != TARGET:
            continue
        yield row, endpoint

def rotate_and_verify(...):
    for row, endpoint in pick_candidate(fetch_rows()):
        write_ovpn(row)          # or push Mihomo openvpn proxy
        restart_gateway()        # or rely on mihomo dial
        try:
            geo = socks_geo(...)
        except Exception as e:
            blacklist_add(endpoint, f"probe_fail {e}")
            continue
        got = normalize_cc(geo.get("countryCode"))
        if got != TARGET:
            blacklist_add(endpoint, f"geo_mismatch want={TARGET} got={got}")
            continue                 # IMPORTANT: do not accept
        save_state(endpoint, geo)    # measured_cc, city, isp
        return True
    return False
```

Minimal UK-focused diff mindset vs a naive manager:

1. Normalize `UK` → `GB` at ingest **and** at compare time.  
2. Never accept a node solely because the CSV said UK.  
3. Geo probe is part of `rotate()` success, not a later cosmetic check.  
4. Blacklist on mismatch so the sticky primary cannot “stick” to Kyiv again.

## Operator-facing honesty

When reporting to a human:

> 你选的是英国 (GB)。池子标记也是 UK，但连上后实测是乌克兰·基辅。已拉黑该节点并换线。  
> Requested GB; pool labeled UK; measured UA/Kyiv. Blacklisted; rotating.

Do not silently keep the wrong exit. Do not relabel UA as UK in the client remark.

## Related

- Architecture: [mihomo-multicountry.md](mihomo-multicountry.md)  
- Parent skill Section on country measurement / heal scripts (`heal.sh.example` already compares `countryCode`)
