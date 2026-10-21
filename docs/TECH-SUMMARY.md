# 技术总结（2026-10-21）

## 流程

1. 交钥匙：AI 生成专用 ed25519 钥匙（注释 homeline-agent），用户在 VPS 终端粘一条命令把公钥加进 authorized_keys 并打印公网 IP，只回 IP + 用户名；不问密码，私钥不外传；交付时给撤销命令 `sed -i '/homeline-agent$/d' ~/.ssh/authorized_keys`。
   - 备用：用户不会用终端时，在 AI 的远程浏览器里打开商家网页控制台，用户自己登录（密码/2FA/验证码都由用户输），AI 在网页终端里粘贴命令；SSH 不通就全程在网页终端里操作。网页控制台容易吞长粘贴，要分短行或用 heredoc，粘完先核对再执行。
2. 第 0 阶段只读扫描（`templates/scan-vps.sh`）：系统、架构、内存/swap/磁盘、虚拟化与 TUN、公网 IP 归属、Docker、监听端口、容器、服务、已有面板/代理、防火墙、VPN Gate 可达性、UDP 出站。
3. 按决策表生成一份带默认值的方案（路线 A、KR+US、空闲端口、按需 swap/Docker、巡检关），没反对就开工；只有没 TUN、会动到原有服务、或有破坏性操作才硬停。
4. 搭建 → 实测出口 → 交付链接和二维码。

## 架构

```text
客户端 ──VLESS+Reality+Vision──▶ VPS 上独立 Xray（每条线一个端口、一个 systemd 服务）
      ──SOCKS5(带认证, 只绑 127.0.0.1)──▶ v2 网关容器（每条线一个）
           ├─ OpenVPN 客户端 → VPN Gate 志愿者节点（目标国家）
           ├─ microsocks（容器内 1080）
           ├─ kill switch：容器内 OUTPUT 默认 DROP，只放行 lo / tun+ / 回包 / 到 VPN 远端的 TCP 或 UDP
           └─ 看门狗：每 20s 用 pgrep 查 OpenVPN；每 ~60s 经 tun0 请求 generate_204，连续 3 次失败退出 → Docker 原节点重启
```

- 挑节点：`fetch_candidates.py` 拉 VPN Gate 官方列表 → 按国家过滤 → 丢掉 ping 无效的 → TCP 优先、UDP 其次 → 按延迟升序、速度降序 → 默认排除 SoftEther（AS36599, 219.100.37.x）。
- 扫描：`scan.sh` 在临时容器（48MB 内存上限）里逐个连，出现 AUTH_FAILED / Connection refused 等失败信号立刻跳过；连通后校验出口 ≠ VPS IP 且国家正确，才算 WORKING。
- 换节点只替换 `client.ovpn` 并重启网关；Xray 的 UUID、端口、Reality 密钥不变，所以客户端链接永远不变。
- 健康模式两种：**仅每分钟自检**（默认，够用），或者 **再加 heal.sh 定时巡检**（可选，自动换掉死节点）。
- 不用管理器容器，不挂 docker.sock，不碰现有面板。

## 已验证结果

| 项目 | 结果 |
|---|---|
| 实测机（示例）：512MB / 1 vCPU / Debian 13（加 1GB swap） | 3 条线并行运行，稳态约 200MB+ 可用；扫描必须串行 |
| KR | 出口为韩国大型运营商宽带，hosting=false，外部客户端 loc=KR |
| JP | 能通，但排名靠前的节点几乎都是 SoftEther 网段，不算家宽 |
| US | 能通，地区运营商，hosting=false，可用节点只有个位数 |
| UK | 测试期间 0 个节点 |
| kill switch | 杀掉 OpenVPN 后 SOCKS 无出口，不漏 VPS IP |
| 自动恢复 | OpenVPN 进程死掉：修复后的看门狗（pgrep）约 20 秒内重启容器并原节点重连（已实测）；隧道假活：约 3 分钟内重启 |
| 手机端 | 待测 |

## 坑与解决

0. **先扫描再动手**：机器一律当未知机器处理，端口、服务、防火墙都以扫描结果为准，不套用任何作者机器上的端口表。

1. **云安全组 + 系统防火墙都要放行 Xray 端口**，只放一处会出现服务器上能通、手机超时。
2. **VPN Gate 登录文件**：`auth.txt` 两行 `vpn` / `vpn`，扫描和网关都需要。
3. **pidfile 看门狗失效**：OpenVPN 退出时会删掉自己的 pid 文件，`kill -0 $(cat pid)` 永远检测不到 → 改用 `pgrep -x openvpn`。
4. **隧道"假活"**：tun0 在、控制通道在，但数据不通 → 只有真实流量探测能发现，所以看门狗测 generate_204。
5. **没有 kill switch 会泄漏**：隧道死后 microsocks 走 VPS 本机网卡出去，出口变成机房 IP。
6. **Xray 26.x 的 x25519 输出**是 `PrivateKey:` / `Password (PublicKey):`，要用不区分大小写的正则解析；解析为空就停下来看原始输出。
7. **字段名**：必须是 `GATE_USER` / `GATE_PASS`，写错会表现为 SOCKS 认证一直失败。
8. **二维码校验**：没有 OpenCV 时用 zxing-cpp；Debian 12+/Ubuntu 24+ 用 `pip install --break-system-packages zxing-cpp pillow`（或 venv）。
9. **JP 的 SoftEther 陷阱**：VPN Gate 运营方自己的网段，不是家宽；默认排除，用户同意才用，并标注"非家宽"。
10. **节点会死**：志愿者节点随时下线；巡检显示失败，往往是那个国家真没节点，如实报告，不要换国家冒充。
11. **小内存**：扫描一次只跑一个临时容器，用全局锁；网关容器限制 48MB 内存。

## 致谢

候选排序、收 UDP、失败信号立即跳过的思路参考 vpnbox（MIT, https://github.com/sajadinmaker/vpnbox），未直接复制代码。
