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
- **node1**：实验 01 已完成（ops 用户有 sudo；SSH 禁止 root 登录和密码登录；开了 ufw，放行了 OpenSSH 和 Nginx HTTP；时间同步用阿里云 NTP；有 heartbeat.service）。实验 02 装了 Nginx 反向代理 + 负载均衡，web-backend 监听 :8081。实验 03 装了 MySQL 8.0 **从库**（server-id=2，GTID 复制 node2，read_only + super_read_only）
- **node2**：web-backend :8081；MySQL 8.0 **主库**（server-id=1，开启 GTID，配置在 `/etc/mysql/mysql.conf.d/replication.cnf`；库 labdb，账号 `app'@'192.168.56.%` 密码 App@12345，复制账号 `repl'@'192.168.56.11` 密码 Repl@12345）；全量备份放在 `/backup`（属主 vagrant）；Redis（bind 127.0.0.1 192.168.56.12，requirepass Redis@12345）
- **master**：作为客户端发起访问，装了 mysql-client；`~/backup` 存放异地备份副本；Redis 曾误装后已 purge
- 这些服务后续实验（巡检脚本、Ansible、Prometheus）还会用，**不要清理**
- Ubuntu 22.04 的 mysqldump 写的是旧语法 `CHANGE MASTER TO`，不是 `CHANGE REPLICATION SOURCE`

## 已知坑（1GB light 档）
- MySQL 8 安装时会占满内存：apt 看起来卡住，SSH 新连接报 `end of file`。**等几分钟就好**，装完日常运行内存够用。用户已明确不需要为此改方案。
- needrestart 会弹窗（内核待重启、服务重启）：直接回车用默认选项即可。
- 笔记本合盖后虚拟机时钟会变慢：重启 `systemd-timesyncd` 即可，不用重启虚拟机（见 00-lab-env 第 7 步）。master 没有配置免密登录自己，命令里不要写 `ssh master`。
- 详细记录见各实验文档的「踩坑记录」表。

## 写作约定
- 实验按 [_templates/lab.md](_templates/lab.md) 写，故障复盘按 [_templates/incident.md](_templates/incident.md) 写
- 📸 标记的地方要截图，图片放在该目录的 `images/` 下；写到 📸 步骤时提醒用户截图
- **每个含命令的小节开头都要写「在 **主机名** 上：」**，即使大标题里已经写了主机也要写（用户明确要求）；换机器的地方也要再写一次；用户遇到的坑记进该实验的「踩坑记录」（现象 / 原因 / 解决）
- 实验跑通后：勾选验证清单，把文档顶部状态改成 `✅ 已跑通（日期）`，同步更新 README.md 和子目录 README 的状态列
- 状态图标：⬜ 未开始 · 📝 文档已写待验证 · 🟨 进行中 · ✅ 已跑通
- 不提交真实密码、AccessKey、私钥或公司资料（实验用的测试密码除外）

## 和用户协作
- 用户通过视频学过 K8s 和 Ansible，但还没有动手经验；回答要简短、只讲要点，用中文
- 工具注意：Git Bash 的 sed 处理中文会报错（is_mb_char），改中文内容用 Edit 工具
- 提交信息用英文，推送到 origin main

## 进度
- ✅ 00 环境 · ✅ 01 系统初始化 · ✅ 02 中间件（2026-10-01）
- ✅ 03 MySQL 主从 + 备份恢复（2026-10-01）
- ✅ 04 Shell 巡检脚本 + cron（2026-10-03）：master 上的 `~/bin/inspect.sh` 由 cron 每 5 分钟执行，报告写到 `~/inspect/`；node2 上的 `/usr/local/bin/mysql-backup.sh` 由 `/etc/cron.d/mysql-backup` 每天 02:00 执行
- ✅ 05 Ansible 入门（2026-10-03）（在 master 上用 apt 装 Ansible 2.10；项目目录 `~/ansible-lab`；inventory 分为 [web]=node1、[db]=node2、[lab:children]；master 不在 inventory 里；baseline.yml 已对 node1、node2 设置 ClientAliveInterval 300 和 motd）
- 📝 06 Ansible role：文档已写待验证。在全新的 **node3**（192.168.56.13，Vagrantfile 里设了 `autostart: false`）上用 roles baseline/web/redis 交付；inventory 的 [app] 组只有 node3；Vault 密码文件在 master 的 `~/.vault_pass`；node3 的 Nginx 后端是自己和 node2:8081。**不要对 node1、node2 跑 baseline**，它会打开 ufw，挡住 MySQL 复制。做完后由 master 把代码复制到 `/vagrant/export/ansible-lab`，Claude 再把它移到 `05-06-ansible/ansible-lab/` 并提交
