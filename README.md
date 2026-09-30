# ops-lab · 运维自动化实操笔记

从零动手搭建、部署、排障的实验记录。每个实验都可按文档复现，也作为工作中的速查手册。

> 路线规划见 [ops-compass](https://github.com/roccowork/ops-compass)

## 实验目录

| 编号 | 主题 | 成果（一句话） | 状态 |
|------|------|----------------|------|
| 00 | [实验环境](00-lab-env/) | 3 台 Linux 虚拟机 + 网络规划 | ⬜ |
| 01 | [Linux 基础](01-linux-basics/) | 系统初始化脚本、排障命令速查 | ⬜ |
| 02 | [Ansible](02-ansible/) | 一条命令批量初始化服务器，重跑无副作用 | ⬜ |
| 03 | [Docker](03-docker/) | Compose 部署 Web + MySQL + Redis | ⬜ |
| 04 | [Kubernetes](04-kubernetes/) | kubeadm 搭建 3 节点集群并用 Helm 部署应用 | ⬜ |
| 05 | [CI/CD](05-cicd/) | 提交代码自动构建镜像并部署 | ⬜ |
| 06 | [监控告警](06-monitoring/) | Prometheus + Grafana + Alertmanager 告警闭环 | ⬜ |
| 07 | [Terraform](07-terraform/) | 代码创建并销毁一套云上 VPC + ECS | ⬜ |
| — | [故障案例](troubleshooting/) | 模拟故障 → 排查 → 根因 → 修复 | ⬜ |

状态：⬜ 未开始 · 🟨 进行中 · ✅ 完成

## 写作约定

- 每个实验按 [_templates/lab.md](_templates/lab.md) 编写，故障按 [_templates/incident.md](_templates/incident.md) 编写
- 命令可直接复制执行；写明在哪台机器、哪个用户下执行
- **不提交**任何密码、AccessKey、私钥、公司内部 IP 或资料
