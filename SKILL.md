---
name: homeline-residential-node
description: "Use when someone wants to build their own residential-exit (家宽) node: a VPS running a VPN Gate gateway container plus an independent Xray VLESS+Reality inbound, giving a client-usable vless:// link and QR code whose exit IP is a residential ISP IP in a chosen country (JP/KR/UK/US etc.), with health-check and auto-rotate self-healing, or to troubleshoot a homeline whose exit country is wrong, whose exit became a datacenter IP, or whose country has no usable nodes."
---

# Homeline Residential Node (VPS + VPN Gate gateway + independent Xray)

Build a personal residential-exit node: on the operator's own VPS, a gateway container runs an OpenVPN client to a VPN Gate volunteer node and exposes an authenticated SOCKS5 bound to `127.0.0.1` only; a manager container picks nodes by country, health-checks the exit, and rotates on failure; a standalone Xray (not a panel's Xray) serves VLESS+Reality to clients and forwards everything out through that SOCKS. Exit is the residential node's IP, not the VPS.

Goal state: the operator ends with (1) one verified `vless://` link per accepted country line, (2) a scannable QR code image of that link, (3) a measured exit country/ISP that matches what the operator picked, or an explicit operator decision to accept a mismatch, (4) a working patrol/self-heal loop, and (5) at least one real client that connected end-to-end. If any operator input below is missing, stop at the gate and ask. Do not invent VPS logins, passwords, UUIDs, keys, exit countries, or results.

Honesty baseline: this package was distilled from a working multi-country deployment (gateway/manager containers per country, standalone `xray-home-<name>` systemd services, an hourly-style patrol writing a status JSON). Details that were not re-verified on a blank VPS in this pass are marked **待实测确认** in this file. Never present a 待实测确认 item as proven.

## 0. Pre-flight gate (STOP and ask if anything is missing)

Collect every item before touching the VPS. If an item is missing, output the missing list and stop. Never log into a server the operator did not explicitly hand over in this session.

| # | Operator input | Accepted forms | If missing |
|---|---|---|---|
| 1 | VPS login method | SSH target + key/password supplied in session, or "I am already logged in, guide me" | STOP and ask |
| 2 | VPS facts | OS/arch (`uname -a`), has Docker or may install it, `/dev/net/tun` availability if known | Ask operator to run the read-only probe in Step 1/7 |
| 3 | Target country (first line) | One of JP / KR / GB / US, or another VPN Gate country code the operator names | STOP and ask (Step 2/7) |
| 4 | Line name + ports | Line name (lowercase, e.g. `jp`), one public Xray TCP port, one loopback SOCKS port; all unused on that VPS | Propose, confirm, verify free in Step 1/7 |
| 5 | Client target | Shadowrocket / Clash / sing-box / v2rayN (pick at least one for the first test) | Ask; default suggestion is Shadowrocket only if operator confirms |
| 6 | Existing-panel declaration | "This VPS has / has no 3x-ui, x-ui or other panel" | Ask; if it has one, the no-touch rule in Section 1 applies |

Gate rule: after listing what is present and missing, wait. Work allowed before the gate passes is read-only preparation only: reading this skill, probing the VPS (Section 2 read-only commands), and explaining trade-offs. Never install, write configs, open firewall ports, or start containers before the gate passes.

Route-honesty rule (say this in substance at the start): "这条路线必须有一台你自己的 VPS，和 CF 那个不要服务器的包不一样。出口是住宅志愿者节点的 IP，会掉、会换 IP，靠巡检自愈续命；我能保证的只有：部署完实测出口给你看，国家对不对、像不像住宅，你点头才算数。"

## 0A. Beginner wizard (default mode for non-technical operators)

If the operator is non-technical, do NOT hand them Section 3 to execute. Run this dialogue instead: one question at a time, plain language, wait for the answer, validate format, then YOU do the work over SSH. The operator should only need to: hand over VPS access, pick a country, and scan a QR code at the end. Never ask the operator to "edit compose" or "run systemctl".

Mandatory facts to state in plain Chinese at the start:

- "服务器：必须要有一台你自己的 VPS，没有就先停下，要么去买一台，要么改用 CF 那个不要服务器的包。CF 包的出口是机房 IP，这个包的出口是住宅 IP，这是两者最大的区别。"
- "国家：你选哪个国家，我就按哪个国家找住宅节点；但最后以实测出口为准，对不上我不会偷偷换个国家糊弄你，会报给你让你选：接受、换个节点再测、还是换国家。"
- "稳定性：住宅节点是志愿者开的，会掉线、会换 IP，这很正常。系统会自己巡检、自己换节点；但某个国家可能一段时间一个可用节点都没有，到时我如实告诉你，不编假线路。"
- "费用：除了 VPS 本身，没有别的必须花的钱。"

Before W1, you MUST send the operator ONE heads-up card first, as a single message, before asking anything else. Use this card verbatim (fill nothing in):

```text
先花30秒看完, 然后我们一步一步来:
一共7步, 每步我只问一句, 你回一句就行, 部署的活我来做, 不用你动手。
必需: 一台你自己的 VPS(能装 Docker 的 Linux), 这是和 CF 那个包最大的区别, 没服务器这条路走不了。
你要准备: VPS 的登录方式, 想一个要的国家(日/韩/英/美等), 最后用手机客户端扫码。
全程你只做三件事: 1) 把服务器交给我登录, 2) 选国家, 3) 最后扫码验收。
预计耗时: 第一次装通常十几分钟起, 主要看服务器网速和那个国家当下有没有可用住宅节点, 不保证固定时间。
说明: 出口是住宅节点的 IP, 会掉会变, 系统会自动巡检换节点; 最后以实测出口国家为准, 你点头才算定。
```

Progress prefix rule (mandatory): every wizard question must start with "第X/7步". Mapping is fixed: W1 = 第1/7步（服务器）, W2 = 第2/7步（选国家）, W3 = 第3/7步（线路名与端口）, W4 = 第4/7步（客户端）, then deployment is 第5/7步（部署）, verification is 第6/7步（实测出口）, patrol handover is 第7/7步（巡检与交付）. Follow-up questions inside the same W item keep the same prefix. Secrets (`GATE_USER`/`GATE_PASS`, UUID, Reality keys) are NOT wizard steps and get no number: they are generated on the VPS, mentioned only as a note inside 第5/7步.

Wizard steps (ask exactly one at a time; scripts in Chinese you can copy):

- W1 Server. Ask: "第1/7步（服务器）: 你有自己的 VPS 吗?有的话把登录方式发我(地址和密钥/密码只在这次会话里用);还没有的话回 没有,我先跟你说清买什么样的、大概多少钱,你决定了我们再继续。" Wait. Validate: you can actually open an SSH session, or the operator confirms they are logged in and will paste command outputs back. Never ask for credentials the operator did not offer, never store them in this package or any file that ships.
- W2 Country. Run Section 0B. Its question carries the 第2/7步（选国家） prefix. One country for the first line; more countries later by repeating the whole build per country (Section 5).
- W3 Line name + ports. Auto-suggest, do not make them invent: "第3/7步（线路名与端口）: 我建议这条线叫 <国家小写>,对外端口用 <PORT>,可以吗?想改回我一个名字或端口。" Validate: name is lowercase letters/digits, port is 1-65535 and (once you can check) not already listening on the VPS; on conflict pick another port and re-confirm. Never reuse an occupied port, and never pick a port an existing panel is known to use without checking.
- W4 Client. Ask: "第4/7步（客户端）: 你最后用什么上网?小火箭 Shadowrocket / Clash / sing-box / v2rayN,回名字就行,不确定就回 小火箭。" This only chooses the first test format; the `vless://` link itself is the same.
- Then execute Sections 2-4 yourself (第5/7步部署）, Section 4 verification （第6/7步实测出口）, and Section 6 patrol + Section 7 delivery （第7/7步）. At the end deliver only: the verified link, its QR image, and the measured exit country/city/ISP per line. If any step fails twice, stop and report the exact error in plain Chinese instead of improvising fixes on live resources.

## 0B. Country choice: the operator decides (mandatory)

Honesty rule (say this verbatim in substance): "你选国家，我按国家找节点；找到后我实测出口 IP 的国家、城市和运营商报给你，对得上你点头才算定，对不上你选：接受这个实际出口、换下一个节点再测、还是换个国家。我不会把别的国家的出口贴上你选的标签交付。"

- R1 Ask (first line: exactly one country; multi-country is built later line by line): "第2/7步（选国家）: 你想要哪个国家的住宅出口?常见：日本 JP、韩国 KR、英国 GB、美国 US。也可以回你想的其它国家代码，我先查有没有节点再答复你。"
- R2 Availability check: after the operator picks, check whether the node source currently lists any TCP-capable nodes for that country (manager candidate query in Section 3, or a dry look at the list). If none: say so plainly — "这个国家现在一个可用节点都没找到" — and offer: wait/retry later, or pick another country. Never silently substitute another country's nodes.
- R3 Measure, do not assume: a node's claimed country is a lead, not proof. After the line is up, measure the real exit (Section 4, V1-V3) and record requested country vs measured country/city/ISP per attempt.
- R4 Operator decides, loop: report "第6/7步（实测出口）: 你选的是 X，实测出口是 Y（城市 Z，运营商 W)。1) 就用这个 2) 换下一个节点再测 3) 换个国家。回数字。" Choosing 2 triggers a manager rotation and a re-measure; choosing 3 returns to R1. Never end the build on an unaccepted country mismatch.
- R5 Label honestly: the delivered link's label/remark must carry the MEASURED country (e.g. `Home-<MEASURED_CC>`), not only the requested one. Record in the Final Delivery Checklist: requested country, measured country/city/ISP, exit IP at delivery time (with a note that it will change), verification method, and date.

## 1. No-touch rule for existing panels (hard rule)

If the VPS already runs 3x-ui, x-ui, or any panel: this build must not modify, restart, or rely on that panel's config files, database, processes, Xray binary, or ports. Everything here is standalone: its own directory (`~/vpngw-<name>/`), its own containers (`vpngw-<name>-gateway`, `vpngw-<name>-manager`), its own Xray install dir (`/etc/xray-home-<name>/`), its own systemd unit (`xray-home-<name>.service`), and ports proven free before use. Before writing anything, list listening ports (`ss -lntp`) and existing services/containers; if a chosen port or name collides, change YOUR new line's name/port — never the existing thing. This rule also forbids "borrowing" the panel's subscription system unless the operator explicitly asks for that as a separate task. Default delivery from THIS skill is a standalone link + QR (Section 7).

## 2. Blank-VPS prerequisites (verify read-only first)

Run these read-only probes first and record the answers; do not install anything until Section 3:

```bash
uname -a; cat /etc/os-release | head -3; id; sudo -n true 2>/dev/null && echo sudo-ok || echo sudo-needs-password
ss -lntp 2>/dev/null | head -50          # which ports are already taken?
docker --version 2>/dev/null || echo no-docker-yet
docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | head -30
ls /dev/net/tun 2>/dev/null || echo no-tun-visible
df -h / | tail -1; free -m | head -2
```

Prerequisite checklist for a fresh VPS:

- Linux with systemd and `sudo`/root. Debian/Ubuntu are the known-good family from the source deployment; other distros **待实测确认**.
- CPU arch x86_64 or ARM64/aarch64 (the Xray download differs; the installer picks by `uname -m`). Other arches unsupported.
- Docker Engine + Compose plugin (installed in Section 3 if missing). The gateway needs `NET_ADMIN` and `/dev/net/tun`; some NAT/oversold VPS products block TUN — if `/dev/net/tun` cannot be opened, STOP and tell the operator this VPS cannot run the gateway. **待实测确认** on your exact VPS product.
- One free public TCP port for Xray Reality, opened in BOTH the cloud provider's security group/firewall AND the OS firewall. A port that is open in only one of the two is the classic "works from the VPS itself, times out from the phone" trap.
- One free loopback TCP port for SOCKS. It must bind `127.0.0.1` only.
- Outbound internet from the VPS (to fetch the node list, OpenVPN endpoints, Docker images, Xray release). No inbound ports besides the Xray port and SSH are needed.
- Minimum RAM/disk: **待实测确认** (the source deployment's machine size is not recorded in this package). Do not quote a number you have not tested; if the VPS is very small, say so and watch build logs for OOM.



## 2B. Field test results (2026-10-18, blank-ish 512 MB Debian 13 VPS, x86_64)

One real run was completed on a small pre-existing VPS (1 vCPU / 512 MB RAM / ~9 GB disk) that already hosted an unrelated panel node; the baseline node was inventoried first and never stopped/restarted/reconfigured, and the test was built only in a new `~/homeline-test/` directory on fresh ports. Conclusions below replace guesswork for the items they name; anything not named stays 待实测确认.

- **Host feasibility: PASS with swap.** Without swap the box had ~290 MB available; a 1 GB swap file was added before Docker work. End state with Docker + gateway container + standalone Xray running: ~250 MB available and under 100 MB swap actually used. No OOM was observed in the current boot's kernel log (an older OOM history could not be re-verified after reboot). 512 MB is workable for ONE line; round 2 (Section 2C) measured three lines in parallel as also fine — re-measure before adding more.
- **TUN: PASS.** `/dev/net/tun` existed and OpenVPN brought `tun0` up inside containers (NET_ADMIN + device mapping). A host that lacks TUN would still be a hard stop.
- **Route S (AimiliVPN) on this host: PARTIAL — gateway up, proxy exit FAIL.** Source-built at pinned commit (v2.1.5) in ~22 s; panel and local proxy both bound to `127.0.0.1` only as required; node fetch worked (98 nodes: JP-heavy, plus KR/US/others); generated panel credentials existed in its data volume. BUT: repeated node connects (10 JP + 10 KR + 2 US candidates) either AUTH_FAILED or built the tunnel and then failed its own proxy-exit test; the same US node config proved working minutes later in an isolated bridge container, and a KR node then worked via Route A. Verdict: on this host-network deployment the Route S proxy layer (device-bound proxy/policy-routing interaction) did not deliver traffic. Do NOT present Route S as proven until this is reproduced or fixed on another host; keep Route A as the working default when exits must flow today. The panel/AUTH_FAILED churn also confirms: a large share of listed VPN Gate nodes at any moment simply refuse or die — the Section 0B/4 honesty loop is not optional.
- **Route A minimal gateway: PASS (KR).** A single bridge container (OpenVPN + source-built microsocks, SOCKS published only on a loopback host port, credentials generated on the VPS) with one scanned-working KR config delivered a measured exit: South Korea, Seoul-area city, SK Broadband (AS9318), `hosting=false` from ip-api — i.e. consumer-broadband type, not a datacenter flag. JP was NOT proven working in this run (Aimili attempts failed; the Route A scan found KR first and stopped), so the delivered line of this test is KR, labelled KR. The working node was found by scanning configs in an isolated container — that scan-then-connect step is now the recommended way to pick the first node (Section 3 note).
- **Standalone Xray + real client kernel: PASS.** Xray v26.3.27 (official release, installed only for this test line) served VLESS+Reality on a fresh high port; the OS firewall (ufw, default-drop, previously only SSH + the baseline node's port allowed) had to be explicitly opened for the new port — the classic Section 2 trap is real. Verification: (a) a client-kernel run on the VPS itself returned `loc=KR, colo=ICN`; (b) a real Xray client on a separate machine over the public internet returned the same `loc=KR, colo=ICN` and the same exit as the server-side SOCKS probe. That covers V1–V5 as far as servers can; **V4's phone scan (Shadowrocket on the operator's handset + mobile-network test) is still undone and remains the user's last step.**
- **Link hygiene in this run:** the generated link/keys live only in the new directory on that VPS (files `600`); they were not copied into this package, and the temporary client config used for the external client-kernel test was deleted after the run.

## 2C. Field test round 2 (2026-10-21, same 512 MB VPS): four countries in parallel

Requested: US / JP / KR / UK, one independent Route A line each (own gateway container, own loopback SOCKS port, own standalone Xray unit/port/UUID/Reality keys, own ufw rule). Measured results (exit IPs, links and keys deliberately not recorded here):

| Line | Works | Exit (server SOCKS probe, ip-api) | Real Xray client over public internet (separate machine) |
|---|---|---|---|
| KR | YES | KR, Gyeonggi/Goyang area, Korea Telecom, hosting=false; after the forced node swap: KR, Gimcheon, Hyundai Communications & Network, hosting=false | loc=KR colo=ICN |
| JP | YES (see caveat) | JP, Tokyo/Chiyoda, ISP "SoftEther", hosting=false | loc=JP colo=NRT |
| US | YES (see caveat) | US, Shelton WA, Hood Canal Communications; ip-api returned hosting=false/mobile=true on one query and hosting=true on another | loc=US colo=SEA |
| UK | NO — 本轮无可用 UK 节点 | VPN Gate list had 0 GB rows (0 TCP candidates) at scan time; nothing to try | — |

Caveats stated honestly: the JP exit is registered to "SoftEther" (the VPN Gate project's own operator space) — not a datacenter flag, but not a consumer ISP either, so do not call it 家宽 without qualification. The US pool had exactly 1 TCP candidate in the list (it worked); ip-api's hosting flag was inconsistent for it → 待实测确认 whether it is residential. The phone (Shadowrocket) re-test of the new KR/JP/US links is 未测 in this round.

**512 MB limits, measured:** 3 gateway containers (each capped `--memory 48m`, real use 1-4 MB) + 3 standalone Xray (5-9 MB RSS each) + the untouched baseline panel left ~215 MB available with ~150 MB of the 1 GB swap used; no OOM in kernel logs. The memory risk is not the steady state but the scans: each scan is a temporary OpenVPN container — run them strictly one at a time (the patrol uses a global `flock`) and cap candidates per round. A 4th line would fit in RAM; it was not built only because no UK node existed.

**Leak found and fixed (important):** with the round-1 gateway (no kill switch), when the JP tunnel died (`SIGTERM[soft,auth-failure]` in its OpenVPN log) microsocks kept answering and exited via the VPS's own interface — the SOCKS probe returned the VPS's datacenter IP in Miami. Gateway v2 (`templates/gateway-v2-entrypoint.sh.example` + `gateway-v2.Dockerfile.example`) installs an iptables OUTPUT default-DROP inside the container (allowed: loopback, `tun+`, established replies to SOCKS clients, and TCP to the VPN remote only). Tested: killing OpenVPN in a running v2 gateway → SOCKS probe returned nothing (no leak). The v2 entrypoint also has a watchdog that exits the container if OpenVPN dies so Docker restarts it; that auto-exit path was not observed to fire in the test (restart count stayed 0 before the patrol replaced the node) → 待实测确认.

**KR "phone times out" conclusion (round 1 line):** the phone DID reach the server (Xray log showed the mobile client accepted), port and link parameters were fine; the gateway's `tun0` was up but the KR volunteer node had stopped passing traffic (100% ping loss, SOCKS curl failed, box-side Xray failed the same way). Cause = upstream node died after the tunnel was established, not a link/port/Reality problem. Fix = swap the node; the link stays the same (see Section 6).

## 2A. Route choice: S (simplified, default for beginners) vs A (self-built)

Two deployment routes reach the same client outcome (one verified `vless://` link + QR per accepted country). Pick at the gate, record the choice, and do not mix steps between routes mid-build.

- **Route S — simplified (default when the operator wants the fewest moving parts).** The gateway + node-manager + local SOCKS layers are replaced by ONE upstream runtime: AimiliVPN (OpenMili/aimili-vpngate; see `templates/SOURCES.md` for the full audit — ~2k stars and actively pushed as of 2026-10-18, GPL-family license file, generated panel credentials, leak-guard and fixed-country mode in its docs). You still run THIS skill's own standalone Xray in front of it (Section 3S step 4), because AimiliVPN by itself only offers a local proxy, not a client-facing VLESS+Reality link. What disappears vs Route A: hand-writing the gateway/manager, generating `GATE_USER`/`GATE_PASS`, and babysitting node rotation by hand — the upstream panel does node fetching, testing, switching and health-driven drift. What does NOT disappear: needing a VPS with TUN/root, picking and measuring the country (Section 0B/4), and真机 verification. Route S in this package was field-tested once on 2026-10-18 (Section 2B): it came up but did NOT pass exit traffic on that host, so it remains **待实测确认 / not yet proven**; the first real deployment must be treated as the Route S field test and its results written back into the delivery checklist.
- **Route A — self-built (Section 3 as written).** Our own gateway/manager containers + standalone Xray. More pieces, more control (per-country stacks are proven in the source deployment), and the fallback when: Route S fails its field test, the operator needs several countries at once with independent stacks today, or upstream changes its terms/license in a way the operator rejects.
- **Multi-country honesty for Route S:** AimiliVPN holds ONE active tunnel per instance in its documented modes (smart-auto / fixed-country / fixed-IP). Running several countries at once therefore means several instances, whose host-network panel/proxy ports and routing would collide unless upstream supports multi-instance cleanly — **待实测确认**, do not promise it. Default: Route S = ONE country line per VPS (or per proven instance); multi-country now = Route A. If the operator's first request is "JP+KR+US at once", say this at the gate and default to Route A.
- **Rejected shortcuts (do not resurrect without re-audit):** all-in-one VLESS panels that spawn egress containers through `/var/run/docker.sock` (root-equivalent control plane, and one audited example checks health only every 24h by default); gateways whose runner is `privileged: true`; panels with a documented default password; subscription-converter services as the delivery mechanism (never send links to a public converter); aggregator/crawler-flavoured projects that pool third-party proxies without per-country health evidence. Full per-project reasons: `templates/SOURCES.md`.

Route S safety conditions (all mandatory, they are why S is allowed at all):
1. Pin the exact upstream commit/release you cloned; record it. Prefer building from that checkout over a prebuilt image; if you use an image, verify its publisher and digest yourself — upstream's own compose references an image namespace that differs from the repo owner, which is exactly the kind of thing you check rather than copy blindly. Never deploy floating `latest`/`main` as the plan.
2. Any `curl | bash` installer is a read-first artifact: download it, record its source commit/hash, read it, then decide. If you cannot read it, use the Docker/source path you CAN read, or fall back to Route A.
3. Panel credentials must be the generated ones from first start (upstream stores them in its data dir); save them to the operator's own password keeping, never into this package/chat logs/screenshots. Force a change if any default is ever presented.
4. Keep the panel off the open internet: bind it to `127.0.0.1` and use an SSH tunnel, or restrict the cloud security group to the operator's IP. A random URL path is a seatbelt, not a wall.
5. Keep its local proxy on `127.0.0.1` only. Your Xray talks to it there; nobody else should be able to.
6. Upstream is GPL-family: runtime use is fine; do NOT paste its code into this package or a public repo of the operator's without license compliance.

## 3S. Route S deployment (simplified; replaces Section 3 steps 3-5 for the gateway half)

Execute only if Route S was chosen at the gate. Steps 1-2 of Section 3 (names/ports, prerequisites) still apply, with `<SOCKS_PORT>` = the AimiliVPN local proxy port and no `GATE_USER`/`GATE_PASS` at all on this route.

1. Clone the pinned upstream checkout onto the VPS (outside any existing panel directory), record commit hash + version file contents in your notes (not in this package). Build via its Docker path using `templates/docker-compose.aimili.example.yml` as your starting file (host network, NET_ADMIN/NET_RAW, TUN device, panel bound to localhost, proxy bound to localhost). If upstream's current compose/Dockerfile disagrees with the template, upstream-at-your-pin wins and you note the diff — the template is a checklist, not gospel.
2. First start: retrieve the generated panel address/path/credentials from the location upstream documents for your deployment mode (Docker: its data volume's UI auth file; source install: the installer's printed output). Hand them to the operator once, in-session, and have them save them. Confirm the panel loads over your SSH tunnel / restricted path before continuing.
3. In the panel: update/fetch nodes, filter to the operator's chosen country, run its node test, connect one node (fixed-country mode if the operator wants that country pinned; smart-auto only if they accept country drift within its rules — if smart-auto can leave the chosen country, that conflicts with Section 0B and you must say so and use fixed-country). Then measure the real exit yourself from the VPS shell through the local proxy (`curl --socks5-hostname 127.0.0.1:<SOCKS_PORT> https://api.ipify.org` plus a geolocation lookup). Panel claims are a lead; your measurement is the record (Section 4 V1-V3 apply unchanged).
4. Install standalone Xray exactly as Section 3 steps 6-9, except the outbound uses `templates/xray-config.aimili.json.example` (SOCKS to `127.0.0.1:<SOCKS_PORT>` with NO user/pass — if your pinned AimiliVPN build offers/ requires proxy auth, set it, record that you did, and treat unauthenticated-vs-authenticated as a verified fact of your build, not an assumption). The `GATE_USER`/`GATE_PASS` field-name pitfall does not exist on this route; its equivalent wound is pointing Xray at the panel port instead of the proxy port, or at a proxy that is bound to a different host/port than Xray expects. Check ports before debugging Reality.
5. Continue at Section 4 (verification) and Section 6 (patrol). For patrol on Route S: the upstream's own health/drift is Layer 1; you must still arm the external checker (Layer 2) because only it knows the operator's accepted country and can scream when the exit silently becomes another country or a datacenter. Exit-country-changed is a first-class alarm on this route, not a curiosity.


## 3. Deploy one country line (第5/7步）

Route S users: execute Section 3S instead of steps 3-5 below, then rejoin at step 6. Otherwise: there are two equivalent ways to execute this section: (A) run the bundled one-shot installer script if the operator's environment provides one (it creates the gateway/manager files, `.env`, compose stack, standalone Xray, systemd unit, firewall rule, then prints the link), or (B) perform the same steps manually using `templates/`. Either way the order, checks, and gates below are mandatory. If you only have this package (no installer script), follow path B and treat any sub-step whose upstream file/version you cannot verify as **待实测确认** rather than inventing code. The gateway image builds `microsocks` from source and uses OpenVPN + policy routing (`fwmark`/table rules) inside the container; the manager is a Python loop. Rebuilding those two programs from scratch is out of scope for a wizard run: if neither an installer nor prebuilt gateway/manager sources are available, STOP after Section 2 and tell the operator exactly which piece is missing.

Step order (do not reorder; each step reports before the next starts):

1. Pick unique names/ports. Line name `<NAME>` (lowercase), directory `~/vpngw-<NAME>`, containers `vpngw-<NAME>-gateway` / `vpngw-<NAME>-manager`, Xray dir `/etc/xray-home-<NAME>`, unit `xray-home-<NAME>.service`, public port `<XRAY_PORT>`, loopback port `<SOCKS_PORT>`. Re-run `ss -lntp`: both ports must be free, and the names must not already exist.
2. Install prerequisites: `curl`, `unzip`, `openssl`, `iptables`; install Docker if absent; confirm `docker compose version` works.
3. Generate SOCKS credentials ON THE VPS into the line's `.env` (never in chat, never committed):
   ```bash
   printf 'GATE_USER=gw%s\nGATE_PASS=%s\n' "$(openssl rand -hex 3)" "$(openssl rand -hex 16)" > .env && chmod 600 .env
   ```
   Field-name pitfall (memorize this): the names must be exactly `GATE_USER` and `GATE_PASS`. The gateway entrypoint, the manager's SOCKS health-check, and the Xray outbound all read those exact names. A renamed field does not fail loudly at startup; it shows up later as SOCKS auth failures / health-check loops. If you see that symptom, check field names before debugging anything else.
4. Lay down gateway + manager. Path A: the installer writes `gateway/` (Dockerfile, entrypoint, up/down routing scripts) and `manager/` (Dockerfile, manager program). Path B: copy the operator-provided equivalents into the same layout. Invariants to verify regardless of path:
   - Gateway: waits for `/vpn/client.ovpn`, starts OpenVPN, routes the SOCKS user's traffic into `tun0` while keeping replies to local SOCKS connections on the main interface (policy routing), and starts `microsocks` on container port 1080 with `-u "$GATE_USER" -P "$GATE_PASS"`. It also writes the credentials to a `600` file for the OpenVPN `--up` hook, because that hook does not inherit container env.
   - Manager: reads `COUNTRIES` (comma-separated country codes), `GATEWAY_NAME`, `GATE_USER`, `GATE_PASS`; polls its node-list source(s); filters candidates by country and TCP support; prefers higher score / lower ping; excludes blacklisted IPs; writes the chosen node's OpenVPN config; restarts/points the gateway at it. List source URLs and candidate scoring details are version-specific: **待实测确认** against the manager code you actually deploy; do not hard-code a source URL from memory into a fresh build without checking it resolves.
   - Blacklist behaviour in the known deployment: a node whose gateway log shows `AUTH_FAILED` is blacklisted for 6 hours. Treat the duration as version-specific (**待实测确认** if your manager build differs).
5. Start the stack from `templates/docker-compose.yml.example` (placeholders replaced): `docker compose up -d --build`. First build takes minutes. Then `docker ps` must show both containers up, and `docker logs --tail 50 vpngw-<NAME>-manager` must show it started with the right country and either selected a node or honestly reported none usable.
6. Install standalone Xray (never the panel's): download the official release zip for the VPS arch into `/etc/xray-home-<NAME>/`, `chmod +x`, generate Reality keys (`xray x25519`), a UUID (`xray uuid`), and an 8-byte hex shortId. Parse key output defensively: field labels differ across Xray versions (PrivateKey/PublicKey vs Password wording seen in the wild) — if parsing yields an empty key, STOP and print the raw output for a human to read. Exact upstream version pinning: **待实测确认** for a fresh build; record the version you installed in the delivery checklist.
7. Write Xray config from `templates/xray-config.json.example`: VLESS+Reality inbound on `<XRAY_PORT>` (dest/SNI `<SNI_HOST>:443` — pick a plausible large-site SNI; the known deployment used an Apple hostname, but any choice is **待实测确认** on the target network), outbound SOCKS to `127.0.0.1:<SOCKS_PORT>` with the same `GATE_USER`/`GATE_PASS`, UDP blocked at the Xray routing layer (the known config blocks UDP; if a client needs UDP, that is a separate, explicitly-tested change). `chmod 600` the config (it contains the Reality private key and SOCKS password). Validate: `xray run -test -c <config>` must pass before the service starts.
8. Create systemd unit `xray-home-<NAME>.service` (`ExecStart=<xray> run -c <config>`, `Restart=always`, after network/Docker), `systemctl daemon-reload`, `systemctl enable --now`. Confirm `systemctl is-active` and that the port is listening.
9. Open the firewall for `<XRAY_PORT>/tcp` in the OS firewall AND remind/verify the cloud security group. Verify from outside the VPS if you have any second vantage point; otherwise flag "external reachability confirmed only by the phone test in Section 4" honestly.
10. First exit probe (still 第5/7步， formal acceptance is next step): `curl -s -m 20 --socks5-hostname 127.0.0.1:<SOCKS_PORT> --proxy-user "<GATE_USER>:<GATE_PASS>" https://api.ipify.org`. The known installer retries this for up to ~5 minutes while the first node connects. Empty result is not yet failure: check manager/gateway logs once, then move to Section 4's decision loop rather than looping forever.

Safety rails for every command above: work only inside the new line's directory/unit names; if any command would touch an existing panel, container, or service, stop and rename your line instead. Keep `.env`, configs, and the final link out of shell history sharing, screenshots, and git.

## 4. Verification checklist (第6/7步； nothing ships unverified)

Do every item, in order. A link that has not passed V1-V4 must not be delivered as "done"; it may only be reported as "deployed, not yet verified" with the failing item named.

- V1 SOCKS exit exists: the Section 3 step-10 curl returns an IP. If empty after the manager has had a full rotation cycle: read `docker logs --tail 100 vpngw-<NAME>-manager` and the gateway log; classify (no nodes for country / all AUTH_FAILED / TUN problem / list source unreachable) and report that class. Do not retry blindly more than twice.
- V2 No leak: the SOCKS exit IP must differ from the VPS's own public IP (`curl -s https://api.ipify.org` without proxy). Equal means traffic is bypassing the tunnel: the known manager treats this as `LEAK` and rotates immediately. If you see it in manual testing, stop delivery and fix routing before anything else.
- V3 Country + ISP measured: query a geolocation source for the exit IP and record country code, city, ISP/org. Compare with the operator's requested country and run the Section 0B R4 decision loop on any mismatch. Residential-vs-datacenter judgement: read the ISP/org name and any hosting/datacenter flag your lookup provides (e.g. ip-api's `hosting` field — whether your chosen lookup exposes it is **待实测确认** at runtime). A big-brand ISP/consumer broadband org is consistent with residential; a cloud/hosting org means this node is probably a datacenter in disguise — say so, offer rotate (R4 option 2), and never label it 家宽/residential to the operator.
- V4 Client end-to-end (mandatory): import the exact delivered `vless://` link (or its QR) into the chosen real client on a real device/network, open an IP-lookup page through it, and confirm (a) the page loads, (b) the shown IP/country matches the V3 measurement (allowing for the exit having rotated since — if it changed, re-measure and re-report). A server-side curl through SOCKS (V1-V3) is necessary but NOT a substitute for V4: Reality/SNI/firewall problems only show up from a real client.
- V5 QR decodes to the same link: generate with `templates/make_sub_qr.py`, then run its `--verify` (or scan with the actual phone camera during V4). If OpenCV is absent the script prints `QR_DECODE_SKIPPED` — then the phone scan in V4 is the decode check, and you must say which one actually happened.
- V6 Patrol is armed (Section 6): one patrol run has completed and written a status entry for this line, and the operator knows where the status file lives.

Delivery link format (single line per country; this stack has no hosted subscription endpoint by default):

```text
vless://<UUID>@<VPS_IP>:<XRAY_PORT>?encryption=none&flow=xtls-rprx-vision&security=reality&sni=<SNI_HOST>&fp=chrome&pbk=<REALITY_PUBLIC_KEY>&sid=<SHORT_ID>&type=tcp#Home-<MEASURED_COUNTRY>
```

Build it from the generated values, store it `600` on the VPS (known path: the Xray dir's `client.txt`), and treat it like a password. Multi-country delivery = one such link + QR per country, each measured separately. Aggregating several lines into one subscription URL/file is **待实测确认** (no subscription server exists in the known deployment): if the operator wants one-import convenience, generate a plain text file containing one link per line for client batch-import only after testing that their client actually imports it that way, and label it as a link list, not a subscription.

## 5. Adding more countries

Repeat Sections 2-4 per country with a fresh `<NAME>`, fresh ports, fresh `.env` credentials, fresh UUID/Reality keys, and its own containers/unit. Never share a SOCKS port, Xray port, directory, or credential set between lines: the known deployment runs each country as an independent stack precisely so one country's bad node pool cannot take down another. After each new line, re-run V1-V4 for that line and extend the patrol config (Section 6) before calling it delivered. Note the known patrol scope honestly: in the source deployment only the primary lines were in the heal scope and extra lines were observe-only — replicate that distinction deliberately (heal vs observe-only per line) and write down which is which, rather than assuming every line self-heals.

## 6. Patrol and self-healing (第7/7步）

Two layers exist in the known deployment; keep both, they catch different things:

- Layer 1, manager in-stack (seconds-to-minutes): loops on `CHECK_INTERVAL` (default 60s in the known code). Each cycle it SOCKS-probes the exit; a probe equal to the VPS IP is a leak → rotate now; consecutive probe failures are counted and at `FAIL_THRESHOLD` (3 in the known code) it rotates to the next candidate, blacklisting the old node; nodes showing `AUTH_FAILED` in recent gateway logs are blacklisted proactively (6h in the known code). It also rotates proactively on a schedule/condition in the known code — the exact proactive trigger is version-specific, **待实测确认** against your manager build; do not promise a trigger you have not seen in the code you deployed.
- Layer 2, external patrol (cron/systemd timer on the VPS or an outside watcher): for each line, checks the Xray unit is active, probes the SOCKS exit, measures country/ISP, tracks `consecutive_failed_runs`, attempts/records a heal (manager restart or rotation nudge — the least invasive action that matches the failure; never restart unrelated services), and writes a status JSON in the shape of `templates/homeline-status.example.json`. Notify the human only when failures exceed the threshold AND self-heal failed (known rule: `consecutive_failed_runs > 3` and heal unsuccessful). One patrol implementation (`templates/check-lines.sh.example`) is a skeleton: wire its TODOs to your status writer before relying on it unattended.

**Tested Route A patrol (field round 2):** one systemd timer + oneshot service per line, default **every 12 hours** (`OnCalendar=*-*-* 00/12:07:00` + `RandomizedDelaySec=300`; adjustable — e.g. `*:0/30` for 30 minutes if the operator prefers faster healing at the cost of more scans). `templates/heal.sh.example`: probe via SOCKS → must return an IP that is NOT the VPS IP and whose ip-api countryCode equals the line's country; on success reset the failure counter. On failure increment `<cc>.count`, write `<cc>.status.json`, log to `<cc>.log` (trimmed to 300 lines). First `no_exit` failure only restarts the gateway with the same node; from the 2nd consecutive failure (or immediately on leak/country mismatch) it takes a global lock, fetches the VPN Gate list (`fetch_candidates.py.example`, same country, TCP only, excluding the current node, at most `SCAN_MAX=5` per round), scans them in a temporary memory-capped container (`scan.sh.example` also rejects leaks and wrong countries), overwrites the line's `client.ovpn` in place and restarts ONLY that gateway. Xray (UUID / port / Reality keys / link) is never touched, so the client keeps the same link. Service runs with `Nice=10`, `MemoryMax=80M`.
Test status: forced swap tested once on KR (node deliberately broken → patrol found a new KR node on try 1 → `healed with new node`; md5 of Xray config and `client.txt` unchanged; the unchanged link then passed a real-client test with loc=KR colo=ICN). JP was also auto-healed once by a manual patrol run. The 12-hour timers are armed but their first scheduled firing had not happened at report time → 待实测确认. The round-1 patrol script had a path bug (wrote its state to `/` and pointed at a missing scan script) — it "ran" for days and never healed anything. Lesson: read the patrol's log after the first run; an armed timer is not proof.

Explain to the operator, plainly: "出口 IP 会变是正常现象，不是故障。住宅节点下线、管理器换点，IP 就跟着变；你只要管国家对不对、还能不能连上。哪天某个国家实在没节点了，巡检会一直显示它失败，那是真没有，不是系统偷懒，到时我告诉你，你决定等它恢复还是换国家。"

Patrol status per line must make these readable at a glance: service active?, SOCKS working?, measured exit country/ISP, consecutive failure count, last heal action and whether it worked, last OK time. If your patrol cannot measure one of these, write `null` and a note — never copy yesterday's value forward as if it were fresh.

## 7. Final delivery (only after Section 4 passes)

Deliver, and nothing beyond this list needs the operator's attention:

1. The verified `vless://` link per accepted country (and, if built and tested, the tested link-list file).
2. The QR PNG per link, with V5's decode result stated.
3. A short measured-exit report per line: requested country, measured country/city/ISP, "exit IP will change" note, and which lines are heal-scope vs observe-only.
4. Where things live on the VPS: line directory, unit name, status file path, and the two commands a human would need (`systemctl status xray-home-<NAME>`, `docker logs --tail 50 vpngw-<NAME>-manager`).
5. The Final Delivery Checklist, filled: gate inputs present (no secret values), country requested vs measured per line, V1-V6 results with method (server probe / phone client), Xray version installed, patrol armed yes/no, no-touch rule respected (existing panel untouched) yes/no, date.

Do not deliver: raw `.env` contents, Reality private keys, SOCKS passwords, SSH credentials, or screenshots containing any of them.

## 8. Troubleshooting

| Symptom | Likely cause | What to check / do |
|---|---|---|
| A chosen country has no usable nodes for hours/days (known history: the GB line once failed repeatedly, then recovered on its own) | That country's volunteer pool is empty or all nodes refuse/fail; not your bug | Manager log should say `no usable <CC> TCP nodes` or show repeated rotate failures. Report honestly: keep the line retrying, or operator picks another country (R4 option 3). Never fabricate a working line, never relabel another country's exit as this country. |
| Exit works but measures as a datacenter/cloud ISP, or country is right but ISP looks like hosting | The "residential" node is actually a hosted box, or your lookup flags it as hosting | V3 judgement: tell the operator it does not look residential, offer rotate; if rotations keep landing on hosting ASNs for that country, say that country's pool looks datacenter-heavy right now. |
| SOCKS auth keeps failing; containers are up | Credential field-name or value mismatch | Check `.env` keys are exactly `GATE_USER`/`GATE_PASS`, compose passes those names, Xray outbound user/pass equal `.env`, and the gateway's generated auth file exists with `600`. Fix names, recreate containers. This is the single most common self-inflicted wound in this stack. |
| Exit IP equals the VPS IP | Tunnel down but SOCKS still answering, or policy routing broken | Treat as leak: stop delivering traffic, check OpenVPN is connected in gateway logs (`Initialization Sequence Completed`), check the up/down routing scripts ran, let the manager rotate; re-run V2 before any delivery. |
| Phone times out, server port reachable, Xray log shows the phone connected, but SOCKS/exit dead | The volunteer node died after the tunnel was up (field case KR, 2026-10-18) | Not a link problem: do not regenerate the link. Probe SOCKS, then swap the node (patrol or manual rescan); link stays the same. |
| SOCKS exit equals the VPS IP after a tunnel drop (field case JP) | Gateway without kill switch falls back to the host route | Use gateway v2 (in-container OUTPUT DROP except tun/VPN remote). Patrol treats it as LEAK and rescans immediately. |
| All lines time out at once; Xray log shows the phone connecting; `tun0` up but 100% loss even to the tunnel peer (field case 2026-10-21, KR/JP/US together ~20 min after start; same symptom as KR on 10-18) | VPN Gate tunnels stalled: control channel alive (no ping-restart), data plane dead | Restart the gateway (same node fixed it). Gateway v2 now probes the data plane every ~60s and exits after 3 misses so Docker restarts it; the 12h patrol alone is too slow for this. |
| Phone times out, but VPS-side SOCKS probe works | Cloud security group not opened, Reality SNI/dest blocked, or wrong port in link | Verify the security group AND OS firewall both allow `<XRAY_PORT>/tcp`; re-check the link's port/SNI/pbk/sid against the server config character by character; test from the phone's mobile data, not only Wi-Fi. |
| Xray service fails to start after config edit | Bad config or unparseable Reality keys | `xray run -test -c <config>` and read the error; re-check `x25519` output labels for your Xray version (Section 3 step 6); confirm the config file did not get placeholder text left in it. |
| Gateway container restarts / no `tun0` | VPS blocks TUN or lacks `NET_ADMIN` | `docker logs vpngw-<NAME>-gateway`; test `/dev/net/tun` open inside the container; if the VPS product forbids TUN, this VPS cannot host the gateway — say so and stop. |
| Manager rotates forever, every node fails | Node list source unreachable/changed, or all candidates blacklisted | Check list fetch errors in manager logs; check blacklist state file; if the source format changed, that is a code fix, not a retry loop — stop, report, and mark the source details 待实测确认 for the fix. |
| `AUTH_FAILED` in gateway logs | That volunteer node's credentials/service reject the standard VPN Gate login | Expected background noise at low rates (manager blacklists and moves on); only actionable if it is every node for a country — then see row 1. |
| QR scans but client says invalid link | QR encodes a truncated/edited link, or client lacks Reality support | V5 verify output vs the stored link; confirm client/version supports VLESS+Reality+Vision; regenerate the QR from the stored `client.txt`, never by retyping. |
| Everything worked yesterday, all lines down today | VPS-level event (reboot, Docker down, firewall reset) before any line-level theory | Check `systemctl is-active docker`, each `xray-home-<NAME>`, and `docker ps` first; check the VPS was not suspended by the provider. Only then debug individual lines. |

## 9. Safety and scope notes

- This is a personal-use exit, not an anonymity system: the VPS provider, the residential node's operator, and the services visited each see their piece. Say so if the operator assumes otherwise.
- Volunteer residential nodes are other people's home connections: no bulk traffic, no abuse, no public sharing of links. If the operator wants to share access with others, stop and discuss limits first.
- Legal/ToS risk sits with the operator and their jurisdiction/provider terms; surface it once, plainly, before deploying, and do not proceed on a "just do it anyway" if the operator's stated use is abusive.
- Secrets hygiene: `.env`, Xray configs, `client.txt`, status files with exit IPs — none of these go into git, chat attachments, or public posts. This package ships placeholders only; if you ever find a real value in a file under this skill directory, stop and remove it before sharing the package further.
