# PATCH_NOTES — Homeline OSS upgrade merge

Date drafted: 2026-10-25 (Asia/Shanghai).  
Target: merge into [`free-dam-man/homeline-residential-exit-skill`](https://github.com/free-dam-man/homeline-residential-exit-skill) when GitHub push is authorized.  
This folder is a **scrubbed staging pack** — not a live deploy tree.

## Summary

Document the post-v1 upgrade path without shipping production secrets:

1. Five-country residential self-host framing (JP / HK / KR / GB / US).  
2. Mihomo hot-standby beside sticky Docker SOCKS.  
3. Mandatory post-connect geo verification + blacklist (UK→UA lesson).  
4. Example Mihomo YAML with placeholders only.  
5. Optional CDN DIRECT offload, documented as a trade-off.

## Files to add (suggested paths in the public repo)

| Staging path | Suggested merge path |
|---|---|
| `README_UPGRADE.md` | `docs/UPGRADE-MIHOMO.md` (or keep name; link from root README) |
| `docs/mihomo-multicountry.md` | `docs/mihomo-multicountry.md` |
| `docs/post-connect-geo-gate.md` | `docs/post-connect-geo-gate.md` |
| `templates/mihomo-homeline.example.yaml` | `templates/mihomo-homeline.example.yaml` |
| `PATCH_NOTES.md` | fold into root changelog / this file under `docs/` |

Root `README.md` should gain a short “Upgrade: Mihomo hot-standby + geo gate” bullet pointing at the new docs. Do **not** replace the v1 wizard flow; this is additive.

## Behavioural changes vs v1 Skill (conceptual)

| Area | v1 | Upgrade |
|---|---|---|
| Egress | One Docker OpenVPN gateway per country | Same sticky gateway **plus** Mihomo `type: openvpn` pool + `fallback` |
| Country trust | Measure after up (heal compares `countryCode`) | Elevate to **hard gate**: mismatch → reject + blacklist before accepting rotate |
| UK/GB | Earlier builds often had zero GB candidates | Still pool-dependent; add normalize `UK`→`GB` and refuse lying labels |
| CDN | Not documented | Optional DIRECT offload; default off |
| Secrets | Templates use placeholders | Same hard ban: no live VPS IP, UUID, Reality keys, shortIds, production exit IPs |

## Explicit non-goals for this merge

- No filled `.env`, no real `client.ovpn`, no production `status.json`.  
- No airport / multi-tenant panel.  
- No claim that userspace OpenVPN works on every Mihomo build without pinning + retest.  
- No copy of live exit IPs from operator status files into examples (use RFC 5737 docs ranges).

## Scrub checklist before `git push`

- [ ] `rg` for private VPS IPs (including any historical Oracle/GCP addresses)  
- [ ] `rg` for UUID / pbk / sid / private key PEMs  
- [ ] `rg` for live residential exit IPs from operator status dumps  
- [ ] Confirm example SOCKS passwords are `<ANGLE>` placeholders  
- [ ] Confirm UK lesson uses country/city names only (no production endpoint IP as “the” bad node)

## Suggested root README blurb (CN/EN)

**中文：** 升级说明（可选）：多国粘住 Docker SOCKS + Mihomo OpenVPN 热备、`fallback` 组、连上后强制验国家（池子 `cc` 不可信）。见 `docs/mihomo-multicountry.md` 与 `docs/post-connect-geo-gate.md`。仍是自建，不是机场。

**EN:** Optional upgrade: per-country sticky Docker SOCKS + Mihomo OpenVPN hot-standby with fallback groups, plus mandatory post-connect geo verify (pool `cc` lies). See the docs above. Still self-host — not an airport.

## Credits / related

- Parent skill Route A gateway + heal/scan templates.  
- Mihomo / Clash.Meta userspace OpenVPN (build-dependent).  
- VPN Gate volunteers; treat availability and labels as unreliable.  
- Geo APIs such as ip-api — respect their ToS / rate limits; swap providers if needed.
