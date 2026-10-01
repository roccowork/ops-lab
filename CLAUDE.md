# CLAUDE.md · ops-lab 项目全局备忘

> 给 Claude 看的项目上下文。**回答环境/方案类问题前，先查本文件和仓库里的现有设计，不要凭记忆另起方案。**

## 项目是什么
- 用户从桌面运维转型运维自动化，用 19 个实验（00–18）动手练习，实验清单与进度见 [README.md](README.md)。
- 姊妹仓库 `../ops-automation-roadmap`：职业路线图静态站点（ops-compass，推到 master 由 Cloudflare Pages 自动部署），只是方向参考，不放实验内容。
- 远程仓库：github.com/roccowork/ops-lab，分支 `main`。

## 实验环境（已有设计，别重复造）
- 宿主机：Win11 Home，Ryzen 7 5800H，16GB 内存，VirtualBox + Vagrant，SSH 客户端用 Termius
- 3 台 Ubuntu 22.04（ubuntu/jammy64），各 2 CPU，登录用户 `vagrant`：

| 主机 | IP | light 档（默认） | k8s 档 |
|------|----|------|------|
| master | 192.168.56.10 | 1GB | 4GB |
| node1 | 192.168.56.11 | 1GB | 2.5GB |
| node2 | 192.168.56.12 | 1GB | 2.5GB |

- **内存档位已写在 [Vagrantfile](00-lab-env/Vagrantfile)**：做 K8s 或 ELK 时执行 `$env:LAB_PROFILE="k8s"; vagrant reload`；`$env:` 只对当前窗口有效。
- 不加 swap：之后的 kubeadm 实验要求关闭 swap，内存不够就切到 k8s 档。
- 两块网卡：NAT（enp0s3，上网用）+ Host-Only（enp0s8，192.168.56.0/24，三台互通、Windows 连虚拟机）
- provision.sh 首次启动会自动配置：/etc/hosts 主机名解析、阿里云 apt 源、Asia/Shanghai 时区、常用工具
- 快照 `base` 是干净环境：`vagrant snapshot restore base`
- master 已能用 ed25519 密钥免密登录两台 node（`vagrant` 用户；node1 上的 `ops` 用户也可以），公钥放在 `/vagrant/.keys/master.pub`（已被 gitignore）
- 不要执行 `do-release-upgrade`，三台都保持 22.04

## 各机器当前状态（随实验更新）
- **node1**：实验 01 已完成（ops 用户有 sudo；SSH 禁止 root 登录和密码登录；开了 ufw，放行了 OpenSSH 和 Nginx HTTP；时间同步用阿里云 NTP；有 heartbeat.service）。实验 02 装了 Nginx 反向代理 + 负载均衡，web-backend 监听 :8081
- **node2**：web-backend :8081；MySQL 8.0（库 labdb，账号 `app'@'192.168.56.%` 密码 App@12345，bind 已放开）；Redis（bind 127.0.0.1 192.168.56.12，requirepass Redis@12345）
- **master**：作为客户端发起访问；Redis 曾误装后已 purge
- 这些服务实验 03（MySQL 主从）和 Prometheus 实验还会用，**不要清理**

## 已知坑（1GB light 档）
- MySQL 8 安装时会占满内存：apt 看起来卡住，SSH 新连接报 `end of file`。**等几分钟就好**，装完日常运行内存够用。用户已明确不需要为此改方案。
- needrestart 会弹窗（内核待重启、服务重启）：直接回车用默认选项即可。
- 详细记录见各实验文档的「踩坑记录」表。

## 写作约定
- 实验按 [_templates/lab.md](_templates/lab.md) 写，故障复盘按 [_templates/incident.md](_templates/incident.md) 写
- 📸 标记的地方要截图，图片放在该目录的 `images/` 下；写到 📸 步骤时提醒用户截图
- 每条命令都写明在哪台机器执行；用户遇到的坑记进该实验的「踩坑记录」（现象 / 原因 / 解决）
- 实验跑通后：勾选验证清单，把文档顶部状态改成 `✅ 已跑通（日期）`，同步更新 README.md 和子目录 README 的状态列
- 状态图标：⬜ 未开始 · 📝 文档已写待验证 · 🟨 进行中 · ✅ 已跑通
- 不提交真实密码、AccessKey、私钥或公司资料（实验用的测试密码除外）

## 和用户协作
- 用户通过视频学过 K8s 和 Ansible，但还没有动手经验；回答要简短、只讲要点，用中文
- 工具注意：Git Bash 的 sed 处理中文会报错（is_mb_char），改中文内容用 Edit 工具
- 提交信息用英文，推送到 origin main

## 进度
- ✅ 00 环境 · ✅ 01 系统初始化 · ✅ 02 中间件（2026-10-01）
- 📝 03 MySQL 主从 + 备份恢复：文档已写待验证（node2 主库、node1 从库 GTID 复制；mysqldump + binlog 时间点恢复）
