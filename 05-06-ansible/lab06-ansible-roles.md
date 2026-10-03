# 06 · Ansible role 化：新机器一键交付实验 01、02 的成果

> 状态：📝 文档已写，待验证

## 目标
把实验 01（系统初始化）和实验 02（Nginx + 后端 + Redis）里手敲的几十条命令，写成 3 个可复用的 **role**，然后：

```
全新的 node3 ──ansible-playbook site.yml（一条命令）──▶ 和 node1 一样加固、能跑 Nginx 负载均衡和 Redis
                       再跑一次 ──▶ changed=0（幂等）
                       有人手工改了配置 ──▶ --check --diff 发现漂移，再跑一次自动纠正
```

| role | 对应实验 | 做什么 |
|------|----------|--------|
| `baseline` | 01 | ops 账号 + 公钥、SSH 加固、阿里云 NTP、ufw 防火墙 |
| `web` | 02-A | Nginx 反向代理 + 负载均衡、Python 后端（systemd 托管） |
| `redis` | 02-C | Redis 远程访问 + 密码（密码用 **Vault** 加密存放） |

**为什么重要：** 面试问 Ansible，一定会追问“role 目录结构”“变量优先级”“密码怎么管理（Vault）”“template 和 copy 的区别”“怎么保证幂等”。“新机器一条命令交付”也是简历上最有说服力的一句话。

## 环境
| 主机 | 角色 |
|------|------|
| master | 控制节点，所有 ansible 命令在这里执行（沿用实验 05 的 `~/ansible-lab`） |
| node3 | **新机器**（192.168.56.13），本实验的交付对象 |
| node2 | 提供一个后端（node3 的 Nginx 会把一半请求转给它）；用它的 redis-cli 远程测试 node3 的 Redis |

- 为什么不直接在 node1、node2 上跑：它们上面跑着实验 03 的主从复制和实验 04 的备份，`baseline` 会在 node2 上打开防火墙，挡住 MySQL 复制。新机器最能证明“一条命令交付”。
- node3 是 1G 内存，4 台虚拟机一共 4G，笔记本完全够用。实验结束可以删掉 node3。

> 本文档里的密码 `Ops@12345`、`Redis@12345`、`LabVault@2026` 仅用于实验。

---

## A. 准备 node3

### A1. 启动 node3
Vagrantfile 里已经加好了 node3（`autostart: false`：平时 `vagrant up` 不会启动它）。

在 **Windows PowerShell** 上（`00-lab-env` 目录）：
```powershell
vagrant up node3
vagrant status        # node3 running，其他三台不受影响
```
首次启动会自动执行 provision.sh（hosts、阿里云源、时区、常用工具），大约 3–5 分钟。

### A2. 让 master 能免密登录 node3
在 **node3** 上（Windows PowerShell 里执行 `vagrant ssh node3` 登录）：
```bash
cat /vagrant/.keys/master.pub >> ~/.ssh/authorized_keys
```
在 **master** 上：
```bash
echo "192.168.56.13 node3" | sudo tee -a /etc/hosts   # master 的 hosts 是之前生成的，没有 node3
ssh node3 hostname                                    # 第一次输入 yes，输出 node3
```

### A3. 加入 inventory
在 **master** 上（`~/ansible-lab` 目录）：
```bash
cat >> inventory.ini <<'EOF'

[app]
node3
EOF
ansible-inventory --graph
ansible app -m ping
```
`app` 组只有 node3，所以后面的 playbook 不会碰到 node1、node2。

---

## B. role 目录结构

### B1. 建目录
在 **master** 上（`~/ansible-lab` 目录）：
```bash
mkdir -p roles/{baseline,web,redis}/{tasks,handlers,templates,defaults}
mkdir -p group_vars/app
tree roles
```
| 目录 | 放什么 |
|------|--------|
| `tasks/main.yml` | 这个 role 要做的事（必须有） |
| `handlers/main.yml` | 被 notify 才执行的操作，如重启服务 |
| `templates/` | Jinja2 模板（`.j2`），渲染变量后再下发 |
| `defaults/main.yml` | 变量**默认值**（优先级最低，随时可被覆盖） |
| `group_vars/app/` | 只对 `app` 组生效的变量（优先级高于 defaults） |

`{a,b,c}` 是 bash 的花括号展开，一条 mkdir 建出 12 个目录。标准做法也可以用 `ansible-galaxy init roles/xxx` 生成完整骨架，本实验只建用得到的目录。

---

## C. baseline role（实验 01）

### C1. 默认变量
在 **master** 上（`~/ansible-lab` 目录）：
```bash
cat > roles/baseline/defaults/main.yml <<'EOF'
---
ops_user: ops
ntp_server: ntp.aliyun.com
ssh_max_auth_tries: 3
ssh_client_alive_interval: 300
ssh_client_alive_count_max: 2
EOF
```

### C2. SSH 加固模板
在 **master** 上（`~/ansible-lab` 目录）：
```bash
cat > roles/baseline/templates/10-hardening.conf.j2 <<'EOF'
# {{ ansible_managed }}
PermitRootLogin no
PasswordAuthentication no
MaxAuthTries {{ ssh_max_auth_tries }}
ClientAliveInterval {{ ssh_client_alive_interval }}
ClientAliveCountMax {{ ssh_client_alive_count_max }}
EOF
```
和实验 01 的 `10-hardening.conf` 内容一样，只是把数字换成了变量。`{{ ansible_managed }}` 会渲染成 `Ansible managed`，提醒别人“这个文件由 Ansible 管理，别手改”。

**template 和 copy 的区别（面试高频）：** `copy` 原样复制文件；`template` 先用变量渲染 `{{ }}`、`{% for %}` 再下发。

### C3. 任务
在 **master** 上（`~/ansible-lab` 目录）：
```bash
cat > roles/baseline/tasks/main.yml <<'EOF'
---
- name: 创建运维账号并加入 sudo 组
  ansible.builtin.user:
    name: "{{ ops_user }}"
    shell: /bin/bash
    groups: sudo
    append: true
    password: "{{ ops_password | password_hash('sha512', 'opslabsalt') }}"
    update_password: on_create

- name: 给运维账号配置 master 的公钥
  ansible.posix.authorized_key:
    user: "{{ ops_user }}"
    key: "{{ lookup('file', lookup('env', 'HOME') + '/.ssh/id_ed25519.pub') }}"

- name: SSH 加固
  ansible.builtin.template:
    src: 10-hardening.conf.j2
    dest: /etc/ssh/sshd_config.d/10-hardening.conf
    mode: "0644"
    validate: /usr/sbin/sshd -t -f %s
  notify: 重启 sshd

- name: 时间同步使用阿里云 NTP
  ansible.builtin.lineinfile:
    path: /etc/systemd/timesyncd.conf
    regexp: '^#?NTP='
    line: "NTP={{ ntp_server }}"
  notify: 重启 timesyncd

- name: 防火墙放行 SSH（必须先放行再启用）
  community.general.ufw:
    rule: allow
    name: OpenSSH

- name: 防火墙默认拒绝入站，并启用
  community.general.ufw:
    state: enabled
    direction: incoming
    policy: deny
EOF
```
**两个幂等细节：**
| 写法 | 原因 |
|------|------|
| `password_hash('sha512', 'opslabsalt')` 固定盐值 | 不写盐值时每次生成的哈希都不同，Ansible 会认为密码变了，**每次都 changed** |
| `update_password: on_create` | 只在创建用户时设置密码，之后用户自己改了密码也不会被覆盖 |

- `lookup('file', ...)` 读的是**控制节点（master）**上的文件，不是 node3 上的；`lookup('env', 'HOME')` 取 master 上当前用户的家目录。
- `ops_password` 这个变量还没定义，在 E 部分用 Vault 定义。

### C4. handlers
在 **master** 上（`~/ansible-lab` 目录）：
```bash
cat > roles/baseline/handlers/main.yml <<'EOF'
---
- name: 重启 sshd
  ansible.builtin.service:
    name: ssh
    state: restarted

- name: 重启 timesyncd
  ansible.builtin.service:
    name: systemd-timesyncd
    state: restarted
EOF
```

---

## D. web role（实验 02-A）

### D1. 默认变量和模板
在 **master** 上（`~/ansible-lab` 目录）：
```bash
cat > roles/web/defaults/main.yml <<'EOF'
---
backend_port: 8081
backend_servers:
  - "127.0.0.1:{{ backend_port }}"
EOF

cat > roles/web/templates/index.html.j2 <<'EOF'
<h1>Hello from {{ ansible_hostname }}</h1>
EOF

cat > roles/web/templates/web-backend.service.j2 <<'EOF'
# {{ ansible_managed }}
[Unit]
Description=Lab web backend
After=network.target

[Service]
ExecStart=/usr/bin/python3 -m http.server {{ backend_port }} --directory /srv/web
User=www-data
Restart=always

[Install]
WantedBy=multi-user.target
EOF

cat > roles/web/templates/lab.conf.j2 <<'EOF'
# {{ ansible_managed }}
upstream backend {
{% for server in backend_servers %}
    server {{ server }};
{% endfor %}
}

server {
    listen 80 default_server;
    server_name _;

    access_log /var/log/nginx/lab_access.log;
    error_log  /var/log/nginx/lab_error.log;

    location / {
        proxy_pass http://backend;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_connect_timeout 2s;
    }

    location /nginx_status {
        stub_status;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
```
- `{{ ansible_hostname }}` 是 facts（实验 05 B4 讲过），自动取每台机器的主机名。
- `{% for %}...{% endfor %}` 是 Jinja2 循环：`backend_servers` 列表里有几个后端，就生成几行 `server`。加机器只改变量，不改模板。

### D2. 任务和 handlers
在 **master** 上（`~/ansible-lab` 目录）：
```bash
cat > roles/web/tasks/main.yml <<'EOF'
---
- name: 安装 Nginx
  ansible.builtin.apt:
    name: nginx
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: 后端网页目录
  ansible.builtin.file:
    path: /srv/web
    state: directory
    mode: "0755"

- name: 后端首页
  ansible.builtin.template:
    src: index.html.j2
    dest: /srv/web/index.html
    mode: "0644"

- name: 后端 systemd 服务文件
  ansible.builtin.template:
    src: web-backend.service.j2
    dest: /etc/systemd/system/web-backend.service
    mode: "0644"
  notify: 重启 web-backend

- name: 启动后端并设为开机自启
  ansible.builtin.systemd:
    name: web-backend
    state: started
    enabled: true
    daemon_reload: true

- name: Nginx 站点配置
  ansible.builtin.template:
    src: lab.conf.j2
    dest: /etc/nginx/sites-available/lab.conf
    mode: "0644"
  notify: 重载 nginx

- name: 启用站点（软链接）
  ansible.builtin.file:
    src: /etc/nginx/sites-available/lab.conf
    dest: /etc/nginx/sites-enabled/lab.conf
    state: link
  notify: 重载 nginx

- name: 删除默认站点
  ansible.builtin.file:
    path: /etc/nginx/sites-enabled/default
    state: absent
  notify: 重载 nginx

- name: 防火墙放行 80
  community.general.ufw:
    rule: allow
    name: Nginx HTTP

- name: 确保 Nginx 运行并开机自启
  ansible.builtin.service:
    name: nginx
    state: started
    enabled: true
EOF

cat > roles/web/handlers/main.yml <<'EOF'
---
- name: 重启 web-backend
  ansible.builtin.systemd:
    name: web-backend
    state: restarted
    daemon_reload: true

- name: 重载 nginx
  ansible.builtin.service:
    name: nginx
    state: reloaded
EOF
```
3 个任务都 notify 了“重载 nginx”，但 handler **只会在最后执行一次**——这就是 handler 比“每步后面跟一个 reload”好的地方。

---

## E. redis role + Vault

### E1. redis role
在 **master** 上（`~/ansible-lab` 目录）：
```bash
cat > roles/redis/defaults/main.yml <<'EOF'
---
redis_bind: "127.0.0.1 {{ ansible_enp0s8.ipv4.address }}"
redis_allow_from: 192.168.56.0/24
EOF

cat > roles/redis/tasks/main.yml <<'EOF'
---
- name: 安装 Redis
  ansible.builtin.apt:
    name: redis-server
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: 监听地址
  ansible.builtin.lineinfile:
    path: /etc/redis/redis.conf
    regexp: '^bind '
    line: "bind {{ redis_bind }}"
  notify: 重启 redis

- name: 访问密码
  ansible.builtin.lineinfile:
    path: /etc/redis/redis.conf
    regexp: '^#?\s*requirepass '
    line: "requirepass {{ redis_password }}"
  no_log: true
  notify: 重启 redis

- name: 防火墙只对内网放行 6379
  community.general.ufw:
    rule: allow
    port: "6379"
    proto: tcp
    from_ip: "{{ redis_allow_from }}"

- name: 确保 Redis 运行并开机自启
  ansible.builtin.service:
    name: redis-server
    state: started
    enabled: true
EOF

cat > roles/redis/handlers/main.yml <<'EOF'
---
- name: 重启 redis
  ansible.builtin.service:
    name: redis-server
    state: restarted
EOF
```
- `ansible_enp0s8.ipv4.address`：从 facts 里取 Host-Only 网卡（enp0s8）的 IP，node3 上就是 192.168.56.13，不用写死。
- `no_log: true`：这个任务的输出不打印到屏幕，防止密码出现在日志里。代价是出错时也看不到详细信息，排错时可以临时去掉。

### E2. 用 Vault 加密密码
密码不能明文写在文件里提交到 Git。Ansible Vault 把变量文件整个加密。

在 **master** 上（`~/ansible-lab` 目录）：
```bash
# 1) Vault 的主密码存到文件里，只有自己能读（不要放进项目目录，不要提交）
echo 'LabVault@2026' > ~/.vault_pass
chmod 600 ~/.vault_pass
echo 'vault_password_file = ~/.vault_pass' >> ansible.cfg

# 2) 创建加密的变量文件（会打开 vim）
ansible-vault create group_vars/app/vault.yml
```
在打开的 vim 里写入，然后 `:wq`：
```yaml
vault_ops_password: "Ops@12345"
vault_redis_password: "Redis@12345"
```
在 **master** 上（`~/ansible-lab` 目录）：
```bash
cat group_vars/app/vault.yml          # 一堆 $ANSIBLE_VAULT;1.1;AES256 开头的密文
ansible-vault view group_vars/app/vault.yml   # 解密查看
```
再写一个**明文**变量文件，引用加密的变量：
```bash
cat > group_vars/app/vars.yml <<'EOF'
---
ops_password: "{{ vault_ops_password }}"
redis_password: "{{ vault_redis_password }}"
backend_servers:
  - "127.0.0.1:8081"
  - "192.168.56.12:8081"
EOF
```
- **为什么分两个文件：** `vars.yml` 能直接看到用了哪些变量（`grep` 得到），具体值藏在 `vault.yml` 里。加密变量统一加 `vault_` 前缀，是 Ansible 官方推荐的写法。
- `backend_servers` 覆盖了 web role 的默认值：node3 的 Nginx 后端 = 自己 + node2。
- 以后要改密码：`ansible-vault edit group_vars/app/vault.yml`。

> 📸 截图：`cat vault.yml` 的密文 + `ansible-vault view` 的明文

---

## F. 一键交付

### F1. 写入口 playbook
在 **master** 上（`~/ansible-lab` 目录）：
```bash
cat > site.yml <<'EOF'
---
- name: 新机器一键交付（实验 01 + 02）
  hosts: app
  become: true
  roles:
    - baseline
    - web
    - redis
EOF
tree -L 3 .
ansible-playbook site.yml --syntax-check
```
role 按顺序执行：`baseline` 先开防火墙，`web`、`redis` 再各自放行端口。

### F2. 第一次运行
在 **master** 上（`~/ansible-lab` 目录）：
```bash
ansible-playbook site.yml
```
node3 是新机器，大部分任务都是 `changed`，最后会依次执行几个 handler。PLAY RECAP 要求 **`failed=0`**。

> 📸 截图：第一次运行的 PLAY RECAP

### F3. 第二次运行：幂等
在 **master** 上（`~/ansible-lab` 目录）：
```bash
ansible-playbook site.yml
```
预期 **`changed=0`**，handler 一个都不执行。如果某个任务每次都 changed，说明它写得不幂等，把输出截图发给 Claude 一起排查。

> 📸 截图：第二次运行 `changed=0`

### F4. 验证交付结果
在 **master** 上：
```bash
for i in 1 2 3 4; do curl -s http://node3; done    # node3、node2 交替：负载均衡生效
ssh ops@node3 whoami                               # ops：账号和公钥都配好了
ssh ops@node3 "sudo -n true" || echo "sudo 要密码（正常）"
ssh -o PubkeyAuthentication=no ops@node3           # Permission denied (publickey)：密码登录已禁止
ansible app -b -m command -a "ufw status"          # 22、80、6379（仅内网）
ansible app -b -m shell -a "sshd -T | grep -Ei '^(permitrootlogin|passwordauthentication|maxauthtries)'"
```
在 **node2** 上（用 node2 的 redis-cli 远程访问 node3，验证 bind、密码和防火墙都对）：
```bash
redis-cli -h 192.168.56.13 ping                    # NOAUTH：没带密码被拒绝
redis-cli -h 192.168.56.13 -a 'Redis@12345' ping   # PONG
```

> 📸 截图：curl 交替结果 + node2 上 NOAUTH 和 PONG

---

## G. 配置漂移：发现并自动纠正

**场景：** 有人登录 node3 手工改了 SSH 配置，生产上这叫**配置漂移**（实际状态和代码描述的不一致）。

在 **master** 上：
```bash
ssh node3 "sudo sed -i 's/MaxAuthTries 3/MaxAuthTries 6/' /etc/ssh/sshd_config.d/10-hardening.conf"
```
在 **master** 上（`~/ansible-lab` 目录）：
```bash
ansible-playbook site.yml --check --diff     # 只检查不修改：会显示 -MaxAuthTries 6 / +MaxAuthTries 3
ansible-playbook site.yml                    # 真正执行：改回 3，并触发重启 sshd
ansible-playbook site.yml                    # 再跑：changed=0
```
定期跑 `--check --diff` 就是最简单的“配置审计”：没有 changed 说明机器和代码一致。

**变量优先级（面试常问）：** 在 **master** 上（`~/ansible-lab` 目录）：
```bash
ansible-playbook site.yml --check --diff -e ssh_max_auth_tries=5
```
会显示要把 3 改成 5（`--check` 不会真改）。命令行 `-e` 的优先级最高，能覆盖 group_vars 和 role defaults。常用的几层从低到高：

```
role defaults  <  inventory / group_vars  <  play vars  <  -e 命令行
```

> 📸 截图：`--check --diff` 显示 MaxAuthTries 的差异

---

## H. 把代码保存到仓库
role 是本实验的成果，要放进 GitHub（Vault 文件是密文，可以提交；`~/.vault_pass` 不在项目目录里，不会带上）。

在 **master** 上：
```bash
mkdir -p /vagrant/export
cp -r ~/ansible-lab /vagrant/export/
ls /vagrant/export/ansible-lab
```
`/vagrant` 就是 Windows 上的 `00-lab-env` 目录。复制完告诉 Claude，Claude 会把它移到 `05-06-ansible/ansible-lab/` 并提交。

---

## 验证清单
- [ ] `ansible-playbook site.yml` 第一次运行 `failed=0`
- [ ] 第二次运行 `changed=0`
- [ ] master `curl node3` 在 node3、node2 之间轮询
- [ ] `ssh ops@node3` 免密登录；密码登录被拒绝
- [ ] node2 访问 node3 的 Redis：不带密码 NOAUTH，带密码 PONG
- [ ] `vault.yml` 是密文，`ansible-vault view` 能看到明文
- [ ] 手工改坏的配置能被 `--check --diff` 发现，并被 playbook 纠正

## 故障演练（选做，推荐）
1. **不幂等的密码：** 把 baseline 里的 `password_hash('sha512', 'opslabsalt')` 改成 `password_hash('sha512')`，并删掉 `update_password: on_create`，连跑两次，看“创建运维账号”这个任务每次都 changed。改回去。
2. **Vault 密码不对：** 把 `~/.vault_pass` 改成错误的密码，运行 playbook，看 `Decryption failed` 报错；改回来。
3. **Nginx 模板写错：** 在 `lab.conf.j2` 里删掉一个分号，运行 playbook，看“重载 nginx”这个 handler 失败；再在 node3 上执行 `sudo nginx -t` 定位行号。改回后重新运行。

每个按 [故障模板](../_templates/incident.md) 在 `troubleshooting/` 写一篇复盘。

## 踩坑记录
| 现象 | 原因 | 解决 |
|------|------|------|
| | | |

（遇到报错把完整输出贴给 Claude，修正后记到这里）

## 回滚 / 清理
在 **Windows PowerShell** 上（`00-lab-env` 目录），实验结束后可以删除 node3，释放 1G 内存：
```powershell
vagrant destroy -f node3
```
roles 已经保存，以后要用随时 `vagrant up node3` + `ansible-playbook site.yml` 重新交付（A2 的公钥步骤要再做一次）。

## 简历表述
> 将服务器初始化（账号、SSH 加固、NTP、防火墙）和 Nginx 负载均衡、Redis 部署封装为 Ansible role，使用 Jinja2 模板、分层变量和 Ansible Vault 管理配置与密码，新服务器一条命令完成交付，重复执行 changed=0；通过 `--check --diff` 发现并纠正配置漂移。
