# 00 · 用 Vagrant 搭建 3 节点实验环境

> 状态：📝 文档已写，待验证

## 目标
一条命令创建 3 台可互相用主机名访问的 Ubuntu 虚拟机，master 能免密 SSH 到两台 node，并保存一个干净快照，后面任何实验搞坏了都能一键还原。

**为什么用 Vagrant 而不是在 VirtualBox 里手点：** 环境写成代码（`Vagrantfile`），坏了能删掉重建，配置能放进 Git——这就是“基础设施即代码”的最小版本。

## 环境

| 主机 | IP | 系统 | 默认内存 / k8s 档 | 角色 |
|------|----|------|-------------------|------|
| master | 192.168.56.10 | Ubuntu 22.04 | 1G / 4G | 控制节点（跑 Ansible、K8s 控制面） |
| node1 | 192.168.56.11 | Ubuntu 22.04 | 1G / 2.5G | 工作节点 |
| node2 | 192.168.56.12 | Ubuntu 22.04 | 1G / 2.5G | 工作节点 |

- 网卡 1：NAT（上网用）；网卡 2：Host-Only `192.168.56.0/24`（三台机器和宿主机互通）
- 宿主机：Windows 11 Home，16GB，VirtualBox + Vagrant 2.4.9
- 文件：[Vagrantfile](Vagrantfile)、[provision.sh](provision.sh)（首次启动自动配置 hosts、阿里云源、时区、常用工具）

## 步骤

### 0. 处理旧环境
你之前的 `ansible-lab` 三台虚拟机目前是“已休眠”，不占内存，可以先保留。
**不要新旧两套同时运行**：内存不够，IP 也可能冲突。确认新环境没问题后，再到旧目录执行 `vagrant destroy` 删除。

### 1. 启动
在 Windows PowerShell 中：
```powershell
cd C:\Users\11051\Documents\Codex\2026-09-18\yu\outputs\ops-lab\00-lab-env
vagrant up
vagrant status
```
第一次会依次创建 master、node1、node2 并执行 provision.sh，大约 5–10 分钟。

> 📸 截图：`vagrant status` 显示 3 台都是 `running`

### 2. 验证网络
```powershell
vagrant ssh master
```
在 master 上：
```bash
ping -c 2 node1
ping -c 2 node2
ping -c 2 mirrors.aliyun.com   # 能上网
```

### 3. 配置 master → node 免密 SSH
**原理：** master 生成一对密钥，私钥留在 master，公钥放进 node 的 `~/.ssh/authorized_keys`；之后 master 登录 node 时用私钥证明身份，不需要密码。Ansible 就靠这个管理机器。

在 **master** 上：
```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
mkdir -p /vagrant/.keys
cp ~/.ssh/id_ed25519.pub /vagrant/.keys/master.pub
exit
```
`/vagrant` 是共享文件夹，对应宿主机的 `00-lab-env` 目录，三台机器都能看到，用它来传公钥。`.keys/` 已加入 `.gitignore`，不会提交。

分别在 **node1**、**node2** 上：
```powershell
vagrant ssh node1
```
```bash
cat /vagrant/.keys/master.pub >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
```

回到 **master** 验证：
```bash
ssh node1 hostname    # 第一次会问 yes/no，输入 yes
ssh node2 hostname
```
输出分别是 `node1`、`node2`，且没有要求输入密码，即成功。

> 📸 截图：master 上 `ssh node1 hostname` 和 `ssh node2 hostname` 的输出

### 4. 保存干净快照
```powershell
vagrant snapshot save base
vagrant snapshot list
```
之后任何实验搞乱了：`vagrant snapshot restore base` 一键回到这里。

> 📸 截图：`vagrant snapshot list` 显示三台都有 `base`

### 5. 切换内存档位（做 K8s / ELK 时再用）
```powershell
$env:LAB_PROFILE="k8s"; vagrant reload     # 切到 k8s 档
$env:LAB_PROFILE="light"; vagrant reload   # 切回默认
```
`$env:` 只在当前 PowerShell 窗口有效，新开窗口默认是 light。

## 验证清单
- [ ] `vagrant status` 三台 running
- [ ] master 能 `ping node1`、`ping node2`、能上网
- [ ] master `ssh node1 hostname` 不要密码
- [ ] `vagrant snapshot list` 有 base

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
| | | |

（遇到报错把完整输出贴给 Claude，修正后记到这里）

## 回滚 / 清理
```powershell
vagrant snapshot restore base   # 回到干净状态
vagrant destroy -f              # 全部删除
```

## 简历表述
> 使用 Vagrant 以代码方式管理多节点实验环境，支持内存档位切换与快照回滚，可一键重建。
