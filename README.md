# ops-lab · 运维自动化实操笔记

从零动手搭建、部署、排障的实验记录。每个实验都可按文档复现，也作为工作中的速查手册。

## 实验环境

笔记本：Ryzen 7 5800H / 16GB / Windows 11 Home，VirtualBox + Vagrant 起 3 台 Ubuntu 22.04（master、node1、node2）。
内存有限，**重型实验（K8s、ELK）一次只开一个**，详见 [00-lab-env](00-lab-env/)。

## 实验清单

按顺序做，后面的实验依赖前面的成果。

| # | 实验 | 目录 | 学到什么 | 状态 |
|---|------|------|----------|------|
| 00 | 用 Vagrant 搭建 3 节点实验环境 + SSH 免密 + 快照 | [00-lab-env](00-lab-env/) | Vagrant、VirtualBox 网卡模式（NAT / Host-Only）、SSH 密钥 | ✅ |
| 01 | 系统初始化：用户、SSH 加固、防火墙、时间同步、systemd | [01-linux-basics](01-linux-basics/01-system-init.md) | Linux 基础运维 | 📝 待验证 |
| 02 | 手动部署 Nginx + MySQL + Redis，并做反向代理 | [01-linux-basics](01-linux-basics/) | 中间件安装、配置、排障 | ⬜ |
| 03 | MySQL 主从复制 + 备份与恢复 | [01-linux-basics](01-linux-basics/) | 数据库高可用基础 | ⬜ |
| 04 | Ansible：inventory、ad-hoc、playbook | [02-ansible](02-ansible/) | 批量管理 | ⬜ |
| 05 | Ansible role 化：把实验 01、02 自动化，重跑 `changed=0` | [02-ansible](02-ansible/) | 幂等、模板、变量、Vault | ⬜ |
| 06 | Docker 基础 + 编写 Dockerfile 构建自己的镜像 | [03-docker](03-docker/) | 镜像、容器、分层、多阶段构建 | ⬜ |
| 07 | Docker Compose 部署 Web + MySQL + Redis | [03-docker](03-docker/) | 多容器编排、网络、数据卷 | ⬜ |
| 08 | 虚拟机上手动装 Prometheus + node_exporter + Grafana | [06-observability](06-observability/) | 指标采集、PromQL、面板 | ⬜ |
| 09 | Alertmanager：服务挂掉 1 分钟内收到告警 | [06-observability](06-observability/) | 告警规则、通知 | ⬜ |
| 10 | ELK 单节点：收集 Nginx 日志并在 Kibana 查询 | [06-observability](06-observability/) | 日志采集与检索 | ⬜ |
| 11 | kubeadm 安装 3 节点集群（装一次，懂原理） | [04-kubernetes](04-kubernetes/) | 控制面组件、证书、containerd | ⬜ |
| 12 | K3s 集群 + 部署应用（Deployment / Service / Ingress / ConfigMap / PV） | [04-kubernetes](04-kubernetes/) | K8s 核心对象 | ⬜ |
| 13 | Helm：安装现成 chart + 编写自己的 chart | [04-kubernetes](04-kubernetes/) | 应用打包与发布 | ⬜ |
| 14 | kube-prometheus-stack + Loki：集群监控与日志 | [06-observability](06-observability/) | 企业级可观测性方案 | ⬜ |
| 15 | GitHub Actions：提交代码自动构建并推送镜像 | [05-cicd](05-cicd/) | CI 流水线 | ⬜ |
| 16 | Argo CD：GitOps 自动部署 + 回滚 | [05-cicd](05-cicd/) | CD、GitOps | ⬜ |
| 17 | Terraform：云上创建并销毁 VPC + 云主机（需云账号） | [07-terraform](07-terraform/) | 基础设施即代码 | ⬜ |
| ∞ | 故障演练：每个实验都故意弄坏一次并写复盘 | [troubleshooting](troubleshooting/) | 排障思路 | ⬜ |

可选进阶（内存允许再做）：Kyverno 策略、Cilium 网络、kubeadm 集群升级。

状态：⬜ 未开始 · 📝 文档已写待验证 · 🟨 进行中 · ✅ 已跑通

## 写作约定

- 每个实验按 [_templates/lab.md](_templates/lab.md) 编写，故障按 [_templates/incident.md](_templates/incident.md) 编写
- 文档中 **📸** 标记处必须截图，图片存到该目录的 `images/` 下
- 命令写明在哪台机器执行；先自己敲，理解“为什么”再往下
- **不提交**任何密码、AccessKey、私钥、公司内部 IP 或资料
