#!/usr/bin/env bash
# 每台虚拟机首次启动时自动执行：主机名解析、国内软件源、时区、常用工具
set -euo pipefail

# 1. 三台机器互相用主机名访问
if ! grep -q "ops-lab" /etc/hosts; then
  cat >> /etc/hosts <<'EOF'
# ops-lab
192.168.56.10 master
192.168.56.11 node1
192.168.56.12 node2
192.168.56.13 node3
EOF
fi

# 2. 换成阿里云镜像源，国内下载更快
sed -i -E 's#http://(archive|security)\.ubuntu\.com/ubuntu#http://mirrors.aliyun.com/ubuntu#g' /etc/apt/sources.list

# 3. 时区
timedatectl set-timezone Asia/Shanghai

# 4. 常用工具
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq vim curl wget net-tools dnsutils htop tree git unzip bash-completion >/dev/null

echo "provision done: $(hostname)"
