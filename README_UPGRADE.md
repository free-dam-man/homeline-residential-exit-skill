# Homeline Upgrade Pack / 家宽升级包（Mihomo 热备 + 连上后验国家）

> **Not an airport.** 这不是卖节点、不绑月费、不托管订阅的「机场」。  
> This is a **self-host** upgrade for people who already run (or will run) their own VPS + VPN Gate residential exits. Code and playbooks stay open; credentials stay on *your* machine.

目标仓库 / Target repo: [`free-dam-man/homeline-residential-exit-skill`](https://github.com/free-dam-man/homeline-residential-exit-skill)

本目录是**脱敏升级说明**，供合并进公开仓。不含真实 VPS IP、UUID、Reality 密钥、shortId、生产出口 IP。

---

## 中文：这包升级了什么

在一代 Skill（每国一条 OpenVPN 网关容器 + 独立 Xray VLESS+Reality）之上，增加三条可落地的能力：

| 能力 | 一句话 |
|---|---|
| **五国家宽自建** | 日本 / 香港 / 韩国 / 英国 / 美国：各国独立入口，出口应是该国住宅运营商宽带，而不是机房 IP。 |
| **Mihomo 热备** | 每国可挂「粘住的 Docker SOCKS 主线」+「用户态 OpenVPN 候选池」；主线挂了用 `fallback` / `url-test` 无感切到热备。 |
| **连上后验国家** | 池子里的 `CountryShort=UK` **不可信**（见过自称英国、出口却是乌克兰基辅）。拨通后必须经 SOCKS 查 `ip-api`（或同类），国家不对就拒绝并拉黑。 |

可选：**CDN DIRECT 分流**——把大站/静态 CDN 域名走 `DIRECT`（或本机出口），减轻家宽隧道压力；默认关闭，由你自己打开。

### 这不是什么

- ❌ 不是付费机场 / 共享订阅  
- ❌ 不是「保证永不掉线、永不换 IP」  
- ❌ 不是匿名工具；住宅出口 ≠ 匿名  
- ❌ 不附带可直接抄作业的生产密钥

### 怎么用（给 AI / 给自己）

1. 先读公开仓主 `README.md` + `SKILL.md`（一代主路线）。  
2. 再读本包：
   - [`docs/mihomo-multicountry.md`](docs/mihomo-multicountry.md) — 多国 + 热备架构  
   - [`docs/post-connect-geo-gate.md`](docs/post-connect-geo-gate.md) — 为什么要验国家、怎么验、UK 补丁思路  
   - [`templates/mihomo-homeline.example.yaml`](templates/mihomo-homeline.example.yaml) — 占位符配置示例  
3. 在**你自己的 VPS**上生成 UUID / Reality 密钥 / SOCKS 账号；永远不要把它们提交进 git。  
4. 交付前实测出口：国家、城市、ASN/运营商、是否机房标记；测出来是什么就如实写。

变更清单见 [`PATCH_NOTES.md`](PATCH_NOTES.md)。

---

## English: what this pack adds

On top of the v1 Skill (per-country OpenVPN gateway container + standalone Xray VLESS+Reality), this upgrade documents three practical pieces:

| Feature | One-liner |
|---|---|
| **5-country residential self-host** | JP / HK / KR / GB(UK) / US — independent lines; exit should be consumer broadband in that country, not a datacenter flag. |
| **Mihomo hot-standby** | Per country: sticky Docker SOCKS primary + userspace OpenVPN candidate pool; `fallback` / `url-test` when the primary dies. |
| **Post-connect geo verify** | Pool `cc` labels lie. Example: claimed UK exited Kyiv, UA. After connect, probe through SOCKS (`ip-api` or similar); reject + blacklist mismatches. |

Optional: **CDN DIRECT offload** — send large CDN domains via `DIRECT` to spare the residential tunnel. Off by default.

### What this is not

- ❌ Not a paid “airport” / shared subscription  
- ❌ Not a promise of always-on / fixed IP  
- ❌ Not anonymity tooling  
- ❌ No production secrets shipped here

### How to use

1. Read the public repo `README.md` + `SKILL.md` first.  
2. Then this pack’s docs + example YAML (placeholders only).  
3. Generate UUID / Reality keys / SOCKS creds **on your VPS**; never commit them.  
4. Measure exit country / city / ASN / hosting flag before calling a line “done”.

See [`PATCH_NOTES.md`](PATCH_NOTES.md) for the merge changelog.

---

## Hard scrub rules (maintainers)

Do **not** put any of the following into this repo:

- Real VPS public IPs (e.g. any live Oracle/GCP box)  
- Real client UUIDs, Reality private/public keys, shortIds  
- Live exit IPs copied from production `status.json` as if they were secrets or “the” official exits  
- SOCKS passwords, SSH keys, panel tokens  

Examples may use RFC 5737 docs IPs (`203.0.113.0/24`, `198.51.100.0/24`) and obvious fakes (`00000000-0000-4000-8000-000000000001`).

## License / disclaimer

Same spirit as the parent skill: learning & network research only; obey local law and VPS ToS. VPN Gate volunteers are unpaid and unreliable by nature. Residential ≠ anonymous. You operate it; you own the consequences.

MIT (same as parent repo when merged).
