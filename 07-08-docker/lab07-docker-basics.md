# 07 · Docker 基础 + 编写 Dockerfile 构建自己的镜像

> 状态：📝 文档已写，待验证

## 目标
1. 在 node3 上装好 Docker（国内源 + 镜像加速），掌握容器的完整生命周期：拉取、运行、查看日志、进入容器、停止、删除。
2. 弄懂数据放在哪里：容器删了数据会不会丢、怎么用挂载保存数据。
3. 自己写 Dockerfile 打包一个小程序：先写**单阶段**（约 300MB），再改成**多阶段构建**（约 15MB），对比镜像分层和构建缓存。
4. 亲手踩一个生产上真实存在的坑：**Docker 映射的端口会绕过 ufw 防火墙**。

**为什么重要：** 容器是 K8s 的基础。面试必问：镜像和容器的区别、镜像分层、多阶段构建为什么能减小体积、`CMD` 和 `ENTRYPOINT` 的区别、容器数据怎么持久化。

## 环境
| 主机 | 角色 |
|------|------|
| node3 | 装 Docker，本实验所有 docker 命令都在这里执行 |
| master | 从外部访问容器映射的端口，验证防火墙 |

- node3 是实验 06 交付的机器：开了 ufw，宿主机的 Nginx 占着 80 端口、Redis 占着 6379。所以本实验的容器都映射到 **8080、8090** 等端口。
- node3 是 `autostart: false`：电脑重启后要在 Windows PowerShell（`00-lab-env` 目录）执行 `vagrant up node3`。
- 默认 light 档（1G）即可。

---

## A. 安装 Docker

### A1. 从阿里云源安装 Docker CE
Docker 官方源在国内很慢，换成阿里云的 docker-ce 镜像源。

在 **node3** 上：
```bash
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu jammy stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
docker --version
systemctl is-active docker          # active
```
- 先导入 GPG 公钥，apt 用它校验下载的软件包有没有被篡改。
- `docker-compose-plugin` 是实验 08 用的 `docker compose` 命令，这里一起装上。

### A2. 让 vagrant 用户不用 sudo 就能执行 docker
在 **node3** 上：
```bash
sudo usermod -aG docker vagrant
exit
```
重新登录 node3 后：
```bash
docker ps                           # 不报 permission denied 即可
```
⚠️ **docker 组的权限等同于 root**（能挂载宿主机任意目录到容器里）。生产环境只给可信的运维账号。

### A3. 配置镜像加速和日志限制
Docker Hub 在国内基本拉不动，要配置镜像加速地址。

在 **node3** 上：
```bash
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://docker.m.daocloud.io",
    "https://docker.1ms.run"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
sudo systemctl restart docker
docker info | grep -A3 "Registry Mirrors"
docker run --rm hello-world         # 出现 Hello from Docker! 说明能拉镜像、能运行
```
| 配置 | 作用 |
|------|------|
| `registry-mirrors` | 拉镜像时先走这些国内加速地址 |
| `log-opts` | 每个容器日志最多 3 个文件、每个 10MB。**不配的话容器日志会无限增长，把磁盘写满**——生产上的真实事故 |

> 加速地址是第三方提供的，可能失效。如果 `hello-world` 拉不下来（`timeout` 或 `not found`），把报错截图发给 Claude，换一个可用的地址。

> 📸 截图：`docker info` 里的 Registry Mirrors + hello-world 的输出

---

## B. 容器基础

### B1. 镜像和容器
在 **node3** 上：
```bash
docker pull nginx:alpine
docker images                                    # 镜像：只读的模板
docker run -d --name web1 -p 8080:80 nginx:alpine
docker ps                                        # 容器：镜像跑起来的实例
curl -I http://localhost:8080                    # HTTP/1.1 200 OK
```
**镜像和容器的关系：** 镜像是“安装包”，容器是“装好并运行起来的程序”。一个镜像可以启动多个容器。

| 参数 | 含义 |
|------|------|
| `-d` | 后台运行 |
| `--name web1` | 给容器起名，后面用名字操作 |
| `-p 8080:80` | **宿主机 8080 → 容器 80**（左边宿主机，右边容器） |
| `nginx:alpine` | 镜像名:标签。`alpine` 表示基于很小的 Alpine Linux |

### B2. 常用操作
在 **node3** 上：
```bash
docker logs web1                  # 容器的标准输出，就是它的日志
docker logs -f --tail 5 web1      # 持续跟踪最后 5 行，另开窗口 curl 一下就能看到新日志，Ctrl+C 退出
docker exec -it web1 sh           # 进入容器内部
```
进入容器后：
```bash
cat /etc/os-release               # Alpine，不是 Ubuntu：容器有自己的文件系统
ps                                # 只能看到容器里的几个进程
exit
```
回到 **node3**：
```bash
docker stop web1                  # 停止
docker ps                         # 看不到了
docker ps -a                      # 加 -a 能看到已停止的容器
docker start web1                 # 再启动
docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' web1   # 容器在 Docker 内部网络里的 IP，如 172.17.0.2
```
**容器的本质：** 宿主机上一个被隔离的进程。在 node3 上执行 `ps aux | grep "nginx: master"`，能直接看到容器里的 nginx 进程。

### B3. 数据：容器删了数据就没了
在 **node3** 上：
```bash
docker exec web1 sh -c 'echo "<h1>written inside container</h1>" > /usr/share/nginx/html/index.html'
curl http://localhost:8080                    # 显示刚写的内容
docker rm -f web1                             # 强制删除容器
docker run -d --name web1 -p 8080:80 nginx:alpine
curl http://localhost:8080                    # 又变回 Welcome to nginx! —— 刚才写的内容没了
```
**原因：** 容器里写的文件只在这个容器自己的“可写层”里，容器删除就跟着删除。镜像本身是只读的，不会被改。

**解决：把宿主机目录挂载进容器。** 在 **node3** 上：
```bash
sudo mkdir -p /srv/docker-html
echo "<h1>from host directory</h1>" | sudo tee /srv/docker-html/index.html
docker rm -f web1
docker run -d --name web1 -p 8080:80 \
  -v /srv/docker-html:/usr/share/nginx/html:ro nginx:alpine
curl http://localhost:8080                    # from host directory
echo "<h1>changed on host</h1>" | sudo tee /srv/docker-html/index.html
curl http://localhost:8080                    # 立刻变了，不用重启容器
```
- `-v 宿主机路径:容器路径:ro`：**bind mount**（绑定挂载），`ro` 表示容器里只读。
- 另一种是 **volume**（`-v 卷名:容器路径`），由 Docker 管理存放位置，实验 08 的 MySQL 数据会用它。

> 📸 截图：删除容器后内容丢失 + 挂载后改宿主机文件立刻生效

### B4. 坑：Docker 端口绕过 ufw（面试加分点）
node3 的 ufw 只放行了 22、80、6379，没有放行 8080。

在 **master** 上：
```bash
curl -s http://node3:8080          # 竟然能访问！
```
在 **node3** 上：
```bash
sudo ufw status                    # 确实没有 8080
sudo iptables -t nat -L DOCKER -n  # Docker 自己加的端口转发规则
```
**原因：** Docker 直接往 iptables 里写规则，而且这些规则在 ufw 的规则**之前**生效，所以 ufw 拦不住 `-p` 映射出去的端口。很多公司就是这样把“只给内部用”的数据库容器暴露到了公网。

**解决：** 只想本机访问的容器，映射时绑定 127.0.0.1。在 **node3** 上：
```bash
docker rm -f web1
docker run -d --name web1 -p 127.0.0.1:8080:80 \
  -v /srv/docker-html:/usr/share/nginx/html:ro nginx:alpine
curl -s http://localhost:8080      # 本机能访问
```
在 **master** 上：
```bash
curl -s -m 3 http://node3:8080 || echo "连不上了（正确）"
```
需要对外开放的服务，再用宿主机的 Nginx 反向代理过去，统一从 80 端口进来。

> 📸 截图：master 访问 node3:8080，绑定 127.0.0.1 前能访问、绑定后连不上

---

## C. 编写 Dockerfile

### C1. 准备一个小程序
用 Go 写一个 20 行的 Web 程序：返回主机名和版本号，外加一个 `/healthz` 健康检查接口。**不需要会 Go**，只要知道它编译后是一个独立的可执行文件——这正好用来演示多阶段构建。

在 **node3** 上：
```bash
mkdir -p ~/labapp && cd ~/labapp

cat > main.go <<'EOF'
package main

import (
    "fmt"
    "net/http"
    "os"
)

func main() {
    version := os.Getenv("APP_VERSION")
    host, _ := os.Hostname()
    http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintf(w, "labapp %s on %s\n", version, host)
    })
    http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
        fmt.Fprintln(w, "ok")
    })
    fmt.Println("listening on :8000")
    http.ListenAndServe(":8000", nil)
}
EOF

cat > go.mod <<'EOF'
module labapp

go 1.22
EOF
```
`main.go` 用空格缩进，**不要用 Tab**：粘贴到终端时，Tab 会触发 bash 的自动补全，把代码弄乱。

### C2. 第一版：单阶段构建
在 **node3** 上（`~/labapp` 目录）：
```bash
cat > Dockerfile.single <<'EOF'
FROM golang:1.22-alpine
WORKDIR /src
COPY . .
RUN go build -o /labapp .
ENV APP_VERSION=1.0
EXPOSE 8000
CMD ["/labapp"]
EOF

docker build -f Dockerfile.single -t labapp:single .
docker images labapp
```
第一次构建要先拉 golang 镜像（约 250MB），需要等几分钟。镜像大约 **300MB**：里面带着整个 Go 编译器，但运行时根本用不上。

### C3. 第二版：多阶段构建
在 **node3** 上（`~/labapp` 目录）：
```bash
cat > Dockerfile <<'EOF'
# ---------- 第 1 阶段：编译 ----------
FROM golang:1.22-alpine AS builder
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 go build -o /labapp .

# ---------- 第 2 阶段：运行 ----------
FROM alpine:3.20
RUN adduser -D -u 10001 app
COPY --from=builder /labapp /usr/local/bin/labapp
USER app
ENV APP_VERSION=1.0
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=2s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8000/healthz || exit 1
CMD ["labapp"]
EOF

cat > .dockerignore <<'EOF'
Dockerfile*
.dockerignore
EOF

docker build -t labapp:1.0 .
docker images labapp                          # 对比：single 约 300MB，1.0 约 15MB
```

**逐条看懂（面试高频）：**
| 指令 | 作用 |
|------|------|
| `FROM ... AS builder` | 第 1 阶段起名 builder，只用来编译 |
| `COPY --from=builder` | 第 2 阶段**只拿编译好的文件**，编译器、源码都留在第 1 阶段，不进最终镜像 |
| `CGO_ENABLED=0` | 编译成不依赖系统 C 库的静态文件，才能在 Alpine 上运行 |
| `RUN adduser` + `USER app` | 用普通用户运行，不用 root：容器被攻破时损失更小 |
| `EXPOSE 8000` | 只是**说明**程序监听 8000，不会自动映射端口，映射还要靠 `-p` |
| `HEALTHCHECK` | Docker 定期访问 `/healthz`，`docker ps` 会显示 healthy / unhealthy |
| `CMD` | 容器启动时执行的命令，`docker run 镜像 其他命令` 可以覆盖它；`ENTRYPOINT` 不会被这样覆盖，常用来固定主程序 |
| `.dockerignore` | 构建时不发送给 Docker 的文件，和 `.gitignore` 类似 |

> 📸 截图：`docker images labapp` 两个镜像的体积对比

### C4. 运行自己的镜像
在 **node3** 上：
```bash
docker run -d --name app1 -p 127.0.0.1:8090:8000 labapp:1.0
sleep 12
docker ps                                     # STATUS 显示 (healthy)
curl http://localhost:8090                    # labapp 1.0 on <容器ID>
docker run --rm labapp:1.0 whoami             # app：不是 root。这里的 whoami 覆盖了 CMD
```
主机名显示的是容器 ID：每个容器有自己的主机名。

> 📸 截图：`docker ps` 显示 healthy + curl 的输出

### C5. 镜像分层和构建缓存
在 **node3** 上（`~/labapp` 目录）：
```bash
docker history labapp:1.0                     # 每条指令一层，能看到每层的大小
sed -i 's/labapp %s on %s/labapp %s running on %s/' main.go
docker build -t labapp:1.1 .
```
观察构建输出：`FROM`、`COPY go.mod`、`adduser` 这些步骤显示 **CACHED**，只有 `COPY *.go` 和它之后的步骤重新执行。

**为什么先 COPY go.mod、再 COPY 源码：** Docker 从**第一个变化的步骤**开始，后面的缓存全部失效。把很少变化的文件（依赖清单）放前面，经常变化的源码放后面，改代码时前面的步骤都能用缓存，构建更快。

### C6. 版本发布和回滚
在 **node3** 上：
```bash
docker rm -f app1
docker run -d --name app1 -p 127.0.0.1:8090:8000 -e APP_VERSION=1.1 labapp:1.1
curl http://localhost:8090                    # labapp 1.1 running on ...

# 发现 1.1 有问题，回滚：换回旧镜像重新启动即可
docker rm -f app1
docker run -d --name app1 -p 127.0.0.1:8090:8000 labapp:1.0
curl http://localhost:8090                    # labapp 1.0 on ...
```
- `-e` 设置环境变量，覆盖 Dockerfile 里的 `ENV`：同一个镜像，靠环境变量适配不同环境。
- **镜像不可变**，回滚就是“用旧标签重新启动”，比在服务器上改代码可靠得多。所以**不要只用 `latest` 标签**，要用明确的版本号。

> 📸 截图：1.1 和回滚后 1.0 的 curl 输出

---

## D. 清理磁盘
在 **node3** 上：
```bash
docker system df                  # 镜像、容器、卷各占多少空间
docker rm -f web1
docker rmi labapp:single          # 删掉单阶段镜像
docker image prune -f             # 删除没有标签的“悬空”镜像（构建过程中产生的）
docker system df
```
`app1` 保留，实验 08 之前可以随时删掉。

---

## E. 把代码保存到仓库
在 **node3** 上：
```bash
mkdir -p /vagrant/export
cp -r ~/labapp /vagrant/export/
ls -a /vagrant/export/labapp
```
复制完告诉 Claude，Claude 会把它移到 `07-08-docker/labapp/` 并提交。

---

## 验证清单
- [ ] `docker run --rm hello-world` 成功（镜像加速可用）
- [ ] 能说清镜像和容器的区别；删除容器后容器里写的数据会丢失
- [ ] bind mount 后改宿主机文件，容器里立刻生效
- [ ] 复现“Docker 端口绕过 ufw”，并用 `127.0.0.1:` 绑定解决
- [ ] 多阶段镜像比单阶段小一个数量级（约 15MB 对 300MB）
- [ ] `docker ps` 显示 healthy；容器内用户是 app 不是 root
- [ ] 改代码重新构建时，前面的步骤显示 CACHED
- [ ] 用旧标签完成回滚

## 故障演练（选做，推荐）
1. **端口冲突：** 在 node3 上 `docker run -d --name x -p 80:80 nginx:alpine`，看 `address already in use`：宿主机的 Nginx 已经占着 80。用 `sudo ss -tlnp | grep :80` 找到是谁占用的。`docker rm -f x` 清理。
2. **容器起不来：** `docker run -d --name bad labapp:1.0 /not-exist`，命令直接报错 `no such file or directory`；`docker ps` 看不到它，`docker ps -a` 能看到它的状态和退出码。生产上更常见的是程序启动后自己崩溃退出，排查顺序一样：`docker ps -a` 看退出码 → `docker logs 容器名` 看日志。`docker rm bad` 清理。
3. **健康检查失败：** `docker run -d --name sick --health-cmd "exit 1" --health-interval 5s labapp:1.0`，等 20 秒，`docker ps` 显示 unhealthy。`docker rm -f sick` 清理。

每个按 [故障模板](../_templates/incident.md) 在 `troubleshooting/` 写一篇复盘。

## 踩坑记录
| 现象 | 原因 | 解决 |
|------|------|------|
| | | |

（遇到报错把完整输出贴给 Claude，修正后记到这里）

## 回滚 / 清理
Docker 保留，实验 08 继续用。只想清掉本实验的容器，在 **node3** 上：
```bash
docker rm -f app1 web1
```

## 面试题速答
**1. 镜像和容器的区别？**
镜像是只读的模板，包含程序和它运行需要的所有文件；容器是镜像运行起来的实例，在镜像上面加了一层可写层。一个镜像可以启动多个容器，它们共享同一份镜像，各自只有自己的可写层。（B1、B3）

**2. 镜像分层是什么？有什么好处？**
Dockerfile 里每条 `RUN`、`COPY` 等指令生成一个只读层，层层叠加成镜像，`docker history` 能看到每一层。容器运行时在最上面加一个可写层，修改文件时先把文件从下层复制上来再改（写时复制）。好处有三个：
- 共享：多个镜像都基于 alpine 时，alpine 那几层在磁盘上只存一份
- 缓存：构建时没变化的层直接复用，所以要把不常变的指令放前面（C5）
- 传输：推送和拉取时只传本地没有的层

**3. 多阶段构建为什么能减小体积？**
前一个阶段装编译器、下载依赖、编译程序，最后一个阶段只用 `COPY --from=` 拿走编译好的文件。最终镜像只包含最后一个阶段的内容，编译器和源码都不会进去。本实验从约 300MB 降到约 15MB。（C3）

**4. CMD 和 ENTRYPOINT 的区别？**
- `CMD`：默认启动命令，`docker run 镜像 其他命令` 会**整个替换**它。C4 里 `docker run --rm labapp:1.0 whoami` 就是用 whoami 替换了 CMD。
- `ENTRYPOINT`：固定的主程序，`docker run` 后面跟的内容会变成它的**参数**，而不是替换它（要替换必须加 `--entrypoint`）。
- 常见搭配：`ENTRYPOINT ["nginx"]` + `CMD ["-g", "daemon off;"]`，主程序固定，默认参数可以被覆盖。

**5. 容器的数据怎么持久化？**
容器可写层里的数据，容器删除时会一起删除（B3 做过演示）。持久化有两种方式：
- **bind mount**：`-v /宿主机路径:/容器路径`，直接用宿主机的目录，适合配置文件、网页文件
- **volume**：`-v 卷名:/容器路径`，Docker 统一管理（在 `/var/lib/docker/volumes/`），适合数据库数据，实验 08 的 MySQL 会用它

**6.（加分）Docker 映射的端口为什么能绕过 ufw？**
Docker 直接往 iptables 写转发规则，这些规则在 ufw 的规则之前生效。只在本机使用的服务，映射时要写成 `-p 127.0.0.1:端口:端口`。（B4）

## 简历表述
> 熟悉 Docker 容器生命周期与数据持久化；编写多阶段构建 Dockerfile（非 root 运行、健康检查、利用分层缓存），将镜像从约 300MB 精简到约 15MB；了解 Docker 端口映射绕过 ufw 的风险并通过绑定地址规避；配置镜像加速和容器日志轮转。
