# 家宽（住宅出口）节点 Skill

把一套「VPS + VPN Gate 住宅节点 + 独立 Xray」的家宽出口经验做成 AI Skill。**主路线是 A**：每条线一个 v2 网关容器（OpenVPN + microsocks + kill switch + 每分钟流量自检），用扫描脚本挑能用的节点，再加一个独立 Xray。不需要管理器容器，也不挂 docker.sock。路线 S（引用上游 AimiliVPN）只是实验选项，首测没跑通出口。两条路线最后都回到同一套实测验收，不许跳。2026-10-18 真机首测（512 MB Debian 13，详见 SKILL.md 第 2B 节）：路线 S 面板/节点拉取正常但代理出口没跑通，暂不算 proven；路线 A 最小网关跑通一条 KR 线（SK Broadband、非机房标记），独立 Xray + 内外两处真实客户端内核验证出口一致，就差用户手机扫码真机测速这最后一步。下载了这个 Skill 的 AI，应能带着小白在一台**自己的 VPS** 上从零部署出一条指定国家的住宅出口线路，最后交付一条可直接导入客户端的 `vless://` 链接和一张可扫的二维码。

## 这是啥

链路（大白话）：

```text
手机/电脑客户端
  -> VLESS + Reality（你 VPS 上的独立 Xray，只监听你选的一个端口）
  -> 本机带认证的 SOCKS5（只绑 127.0.0.1，外网连不上）
  -> 网关容器里的 OpenVPN 客户端
  -> VPN Gate 上某个国家的住宅节点
  -> 互联网（出口 IP 是那个住宅节点的 IP，不是 VPS 的机房 IP）
```

挑节点：`fetch_candidates.py` 从 VPN Gate 公开列表按国家拉候选（TCP 优先、再按延迟/速度排，默认排除 SoftEther 网段），`scan.sh` 在临时容器里逐个试，失败信号立刻跳过。网关自己每分钟测一次真实流量，断流就重启；节点彻底死了可以手动重扫，或者选装 `heal.sh` 定时换节点（可选，不装也行）。

## 和 CF 节点的区别

| | CF 边缘节点（另一个包） | 本包：家宽节点 |
|---|---|---|
| 出口是谁的 IP | Cloudflare 边缘机房 IP | 住宅节点的 IP（运营商宽带） |
| 要不要自己的 VPS | 不要，免费 Cloudflare 账号起步 | **必须要有一台自己的 VPS** |
| 稳定性 | 相对稳 | 住宅节点会掉、会换 IP，要靠巡检自愈 |
| 适合谁 | 先有个能用的节点 | 跑 AI 账号等更在乎「像真人家庭网络」的场景 |
| 成本 | 可零成本 | VPS 的钱（已有 VPS 就不用加钱） |

先说清：住宅出口**不等于**保证某个服务一定不封号、不等于匿名工具。出口国家、运营商以实测为准，AI 测出来是啥就报啥，用户点头才算定。

## 谁适合用

- 有一台能装 Docker 的 Linux VPS（x86_64 或 ARM64 都行），能改防火墙/安全组；
- 想要 JP / KR / UK / US 等国家的住宅出口，且能接受出口 IP 会变、偶尔要换节点；
- 客户端用小火箭 Shadowrocket / Clash / sing-box / v2rayN 等支持 VLESS+Reality 的工具。

不适合：没有 VPS 又不想买的（去用 CF 那个包）；想要固定 IP 的（住宅节点 IP 天天可能变）；把链接公开分享给很多人的（住宅节点带宽和寿命都扛不住）。

## 前置条件

1. 一台 Linux VPS：建议 Debian/Ubuntu，能用 `sudo`，有公网 IPv4。系统版本、最低配置**待实测确认**（现有线路的机器规格未在本包盘点范围内写死）。
2. 能放行一个自选 TCP 端口（云厂商安全组 + 本机防火墙两处都要放）。
3. VPS 上装 Docker（脚本会装），以及 `/dev/net/tun` 可用（绝大多数 VPS 可以； NAT 小鸡/特殊虚拟化先问商家，**待实测确认**）。
4. 一个支持 VLESS+Reality 的客户端。
5. 如果 VPS 上已经有 3x-ui/x-ui 等面板：本包所有东西都用独立目录、独立 Xray、独立 systemd 服务和新端口，**不改面板的配置、数据库和进程**。动手前先查端口占用，撞了就换端口。

## 怎么用

把整个仓库交给 AI。它不会问你密码：它先生成一把专用钥匙，给你一条命令粘到 VPS 终端执行，你只回 IP 和用户名（默认 root）。不会用终端也行：在 AI 的远程浏览器里打开 VPS 商家的网页控制台（如 Vultr View Console、Oracle Cloud Shell/串口控制台、AWS EC2 Instance Connect、GCP 浏览器 SSH、DigitalOcean Droplet Console、Linode Lish，仅举例），你自己登录，AI 来粘贴命令；SSH 不通就全程在网页终端里做。最后交付时附撤销命令 `sed -i '/homeline-agent$/d' ~/.ssh/authorized_keys`。连上后先跑只读扫描 `templates/scan-vps.sh`（不装、不改任何东西），再按扫描结果给你一份带默认值的方案（路线 A、国家 KR+US、空闲端口自动选、内存不足自动加 swap、缺 Docker 自动装、巡检默认关）。你回数字改某项，或者回「继续」；没反对就照默认开工。只有没有 TUN、会动到原有服务、或有破坏性操作时才停下等你。最后以实测出口国家 + 外部客户端连通为准交付。

## 文件清单

| 文件 | 作用 |
|---|---|
| `templates/grant-access.sh.example` | 交钥匙：生成专用 ed25519 钥匙并打印给用户粘贴的一行命令（含撤销命令说明） |
| `templates/scan-vps.sh` | 第 0 阶段只读扫描：系统/架构/内存/虚拟化/TUN/IP 归属/Docker/端口/容器/服务/已有面板/防火墙/VPN Gate 可达/UDP |
| `SKILL.md` | Skill 本体：门禁、向导、部署、选国家、验证、巡检自愈、排障、交付清单 |
| `templates/docker-compose.yml.example` | 可选：单网关容器的 compose 写法（等价于 SKILL.md 第 3 节的 docker run，无管理器、无 docker.sock） |
| `templates/.env.example` | 每条线路的 `.env` 占位符模板（只放键名和生成方法，不放真值） |
| `templates/xray-config.json.example` | 独立 Xray 入站 Reality -> 本机 SOCKS 的配置模板 |
| `templates/check-lines.sh.example` | 巡检脚本骨架（可选）：查 SOCKS 出口、计数、写状态 JSON |
| `templates/gateway-v2.Dockerfile.example` / `gateway-v2-entrypoint.sh.example` | 主路线网关镜像：kill switch + 每分钟流量自检（pgrep 判断 OpenVPN 存活） |
| `templates/fetch_candidates.py.example` / `scan.sh.example` | 拉候选节点 + 扫描挑节点 |
| `templates/heal.sh.example` / `homeline-heal.timer.example` | 可选：定时巡检换节点（参数化路径，间隔自定） |
| `templates/homeline-status.example.json` | 巡检状态文件结构示例（字段结构与现有巡检一致，值全是占位符） |
| `templates/SOURCES.md` | 2026-10-18 上游候选审计表：维护/许可证/采纳或否决理由（运行时引用，不搬代码） |
| `templates/docker-compose.aimili.example.yml` | 路线 S 的 AimiliVPN 容器模板（占位符，本包原创模板，不含上游代码） |
| `templates/xray-config.aimili.json.example` | 路线 S 的 Xray 配置：出站直连 Aimili 本地 SOCKS（无 GATE 凭证） |
| `templates/make_sub_qr.py` | 由链接/订阅地址生成二维码并校验的脚本（改编自 CF 包同名脚本，见文件头来源说明） |

## 安全红线

- `GATE_USER` / `GATE_PASS`、UUID、Reality 私钥/公钥、shortId、完整 `vless://` 链接和二维码 PNG 都是钥匙，不要发到公开仓库、文章、截图。本包全是占位符。
- SOCKS 只绑 `127.0.0.1`，永远不要改成 `0.0.0.0` 裸奔；带认证也不是给你公网用的。
- `.env` 和 Xray 配置文件权限 `600`；订阅/链接只给本人。
- VPN Gate 是第三方志愿者节点列表：节点质量、可用国家随时变，某个国家可能连续几天没可用节点（英国线路历史上就出现过连续失败后自愈）。没有节点就如实说没有，不要编一条假线路交付。
- 出口 IP 是住宅志愿者的网络出口：只做正当自用，不要拿去做滥用、群发、欺诈类事情。

## 发布方式

本包已在 GitHub 公开发布（MIT）。仓库里只放占位符，不含任何真实账号、IP、域名、UUID、令牌或订阅；提 Issue 也请不要贴这些。

## Round 2 additions (2026-10-21)

- `templates/gateway-v2-entrypoint.sh.example`, `gateway-v2.Dockerfile.example`: Route A gateway with in-container kill switch (fixes a measured leak).
- `templates/heal.sh.example`, `fetch_candidates.py.example`, `scan.sh.example`, `homeline-heal.timer.example`: per-line patrol + self-heal (OPTIONAL; interval is the operator's choice, or skip it and rely on the gateway's minute check), swaps only the node so the link never changes. See SKILL.md 2C and 6.

## Round 3 fixes (2026-10-21, clean re-run)

See SKILL.md 2D and `docs/TECH-SUMMARY.md`.

## Round 4 lessons (2026-10-21, independent test on a ~1 GB cloud VM)

容器统一 `--dns 8.8.8.8`（防云元数据 DNS 黑洞）、Xray 模板端口改为数字、外部客户端验证可换独立机器、VPC 云防火墙要单独放行、云上 authorized_keys 可能被重置需重新交钥匙。详见 SKILL.md 2E 节和 `docs/TECH-SUMMARY.md`。
