# 00 · 用 Vagrant 搭建 3 节点实验环境

> 状态：✅ 已跑通（2026-09-30）

## 目标
一条命令创建 3 台可互相用主机名访问的 Ubuntu 虚拟机，master 能免密 SSH 到两台 node，并保存一个干净快照，后面任何实验搞坏了都能一键还原。

**为什么用 Vagrant 而不是在 VirtualBox 里手点：** 环境写成代码（`Vagrantfile`），坏了能删掉重建，配置能放进 Git——这就是“基础设施即代码”的最小版本。

## 环境

| 主机 | IP | 系统 | 默认内存 / k8s 档 | 角色 |
|------|----|------|-------------------|------|
| master | 192.168.56.10 | Ubuntu 22.04 | 1G / 4G | 控制节点（跑 Ansible、K8s 控制面） |
| node1 | 192.168.56.11 | Ubuntu 22.04 | 1G / 2.5G | 工作节点 |
| node2 | 192.168.56.12 | Ubuntu 22.04 | 1G / 2.5G | 工作节点 |

- 网卡：NAT + Host-Only 两块，分工见下
- 宿主机：Windows 11 Home，16GB，VirtualBox + Vagrant 2.4.9
- 文件：[Vagrantfile](Vagrantfile)、[provision.sh](provision.sh)（首次启动自动配置 hosts、阿里云源、时区、常用工具）

### 两块网卡的分工

| 网卡 | 系统里的名字 | 地址 | 作用 |
|------|--------------|------|------|
| 网卡 1：NAT | `enp0s3` | `10.0.2.15`（三台都一样） | **上网**：借 Windows 的网络访问外网（apt 下载、拉镜像） |
| 网卡 2：Host-Only | `enp0s8` | `192.168.56.10/11/12` | **内部互通**：三台之间、以及 Windows ↔ 虚拟机（Termius 连的就是它） |

- **为什么三台 NAT 地址都是 10.0.2.15 却不冲突：** 每台虚拟机的 NAT 是 VirtualBox 单独给它的一个“私有小网络”，彼此隔离，所以地址相同也没关系——但也因此三台**不能**靠 NAT 网卡互相访问。
- **为什么还要 Host-Only：** 它把三台和 Windows 放进同一个网段 `192.168.56.0/24`，Windows 上会多一块 “VirtualBox Host-Only Ethernet Adapter”，地址是 `192.168.56.1`。
- **主机名为什么能 ping 通：** provision.sh 往 `/etc/hosts` 写了 `192.168.56.10 master` 等三行，相当于一个本地的简易 DNS。
- **自己查看：** 在任意一台执行 `ip -br a`(简洁列出所有网卡、网卡状态、IP)，能看到 `enp0s3` 和 `enp0s8` 两块网卡及其地址。

## 步骤

### 1. 启动
在 Windows PowerShell 中：
```powershell
cd C:\Users\11051\Documents\Codex\2026-09-18\yu\outputs\ops-lab\00-lab-env
vagrant up
vagrant status
```
第一次会依次创建 master、node1、node2 并执行 provision.sh，大约 5–10 分钟。

> 📸 截图：`vagrant status` 显示 3 台都是 `running`
![vagrant status 三台 running](images/01-vagrant-status.png)

### 2. 验证网络
> 登录某台机器有两种方式，任选其一：Termius 打开对应标签页（见第 6 步），或在 `00-lab-env` 目录执行 `vagrant ssh 名字`。下文只写“在 xx 上”。

在 master 上：
```bash
ping -c 2 node1 #2表示master向node1发送2个数据包就停止ping
ping -c 2 node2
ping -c 2 mirrors.aliyun.com   # master能上网
```

### 3. 配置 master → node 免密 SSH
**原理：** master 生成一对密钥，私钥留在 master，公钥放进 node 的 `~/.ssh/authorized_keys`；之后 master 登录 node 时用私钥证明身份，不需要密码。Ansible 就靠这个管理机器。

在 **master** 上：
```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519 #ed25519（现代安全算法）
mkdir -p /vagrant/.keys #vagrant 是共享目录
cp ~/.ssh/id_ed25519.pub /vagrant/.keys/master.pub
```
`/vagrant` 是共享文件夹，对应宿主机的 `00-lab-env` 目录，三台机器都能看到，用它来传公钥。`.keys/` 已加入 `.gitignore`，不会提交。

分别在 **node1**、**node2** 上：
```bash
cat /vagrant/.keys/master.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

回到 **master** 验证：
```bash
ssh node1 hostname    # 第一次会问 yes/no，输入 yes
ssh node2 hostname
```
输出分别是 `node1`、`node2`，且没有要求输入密码，即成功。

> 📸 截图：master 上 `ssh node1 hostname` 和 `ssh node2 hostname` 的输出
![master 免密登录 node1、node2](images/02-ssh-nopass.png)

### 4. 保存干净快照
```powershell
vagrant snapshot save base
vagrant snapshot list
```
之后任何实验搞乱了：`vagrant snapshot restore base` 一键回到这里。

> 📸 截图：`vagrant snapshot list` 显示三台都有 `base`
![三台都有 base 快照](images/03-snapshot-list.png)

### 5. 切换内存档位（做 K8s / ELK 时再用）
```powershell
$env:LAB_PROFILE="k8s"; vagrant reload     # 切到 k8s 档
$env:LAB_PROFILE="light"; vagrant reload   # 切回默认
```
`$env:` 只在当前 PowerShell 窗口有效，新开窗口默认是 light。

### 6. 用 SSH 工具连接（Termius）
比 `vagrant ssh` 方便：3 台各开一个标签页，自带 SFTP 传文件。每台新建一个 Host：

| 字段 | 填写 |
|------|------|
| Address | `192.168.56.10` / `.11` / `.12` |
| Port | 22 |
| Username | `vagrant`（Password 留空） |
| Key | Import `00-lab-env\.vagrant\machines\<名字>\virtualbox\private_key` |

`vagrant destroy` 重建后私钥会变，需重新导入。

**两套密钥别搞混：**

| 密钥 | 谁生成 | 用途 |
|------|--------|------|
| `.vagrant\machines\<名字>\virtualbox\private_key` | 首次 `vagrant up` 时 Vagrant 自动生成，每台一把 | Windows → 虚拟机（Termius、`vagrant ssh`） |
| master 的 `~/.ssh/id_ed25519` | 第 3 步手动 `ssh-keygen` | master → node1/node2（Ansible 用） |

> ⚠️ 登录时提示 `New release '24.04' available`，**不要**执行 `do-release-upgrade`：三台系统版本要保持一致，后续文档都按 22.04 写。

### 7. 合盖 / 睡眠后虚拟机时间不对
**现象：** 笔记本合盖后再打开，虚拟机时间停在合盖那一刻；cron 在睡眠期间没有运行，错过的任务也不会补跑。

**原因：** Windows 睡眠时 VirtualBox 会把虚拟机整个冻结，唤醒后虚拟机从冻结处继续运行，时钟就慢了。`systemd-timesyncd` 隔一段时间才对一次时（最长约半小时），所以短时间内不会自己恢复。

**解决：不用重启虚拟机**，重启时间同步服务让它马上对时。在 **master** 上：
```bash
sudo systemctl restart systemd-timesyncd
for h in node1 node2; do ssh $h sudo systemctl restart systemd-timesyncd; done
sleep 5
date                                                    # master 自己
for h in node1 node2; do echo -n "$h: "; ssh $h date; done
timedatectl | grep synchronized                         # System clock synchronized: yes
```
- 循环里**不要写 `ssh master`**：master 没有配置免密登录自己，会弹出 `authenticity of host` 确认，而且也登不上。master 自己直接执行 `date`。
- 需要虚拟机能上网（要连 NTP 服务器）。

## 验证清单
- [x] `vagrant status` 三台 running
- [x] master 能 `ping node1`、`ping node2`、能上网
- [x] master `ssh node1 hostname` 不要密码
- [x] `vagrant snapshot list` 有 base
- [x] Termius 能分别登录 3 台

## 常用命令速查

| 命令 | 作用 |
|------|------|
| `vagrant up [名字]` | 启动（首次会创建） |
| `vagrant halt` | 关机，释放内存 |
| `vagrant suspend` / `resume` | 休眠 / 唤醒 |
| `vagrant ssh 名字` | 登录某台 |
| `vagrant reload` | 重启并应用 Vagrantfile 修改 |
| `vagrant provision` | 重新执行 provision.sh |
| `vagrant snapshot save/restore/list 名称` | 快照 |
| `vagrant destroy -f` | 彻底删除三台（Vagrantfile 还在，可重建） |

## 踩坑记录
| 现象 | 原因 | 解决 |
|------|------|------|
| 合盖唤醒后虚拟机时间停在合盖时刻 | 宿主机睡眠，虚拟机被冻结；timesyncd 对时间隔长 | `sudo systemctl restart systemd-timesyncd`，见第 7 步 |

（遇到报错把完整输出贴给 Claude，修正后记到这里）

## 回滚 / 清理
```powershell
vagrant snapshot restore base   # 回到干净状态
vagrant destroy -f              # 全部删除
```

## 简历表述
> 使用 Vagrant 以代码方式管理多节点实验环境，支持内存档位切换与快照回滚，可一键重建。
