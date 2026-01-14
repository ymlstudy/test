#用 Kyverno + Harbor 实现 Kubernetes 镜像供应链全量接管实战

痛点：k8s集群节点下载镜像时候，因为镜像源都是在国外平台，网络原因下载失败。

解决思路：
1，自建harbor,做k8s的镜像源
Harbor 作为 Docker Registry：通过 Harbor 提供的镜像仓库服务，将应用镜像存储在 Harbor 中。
Kubernetes 拉取镜像：Kubernetes 配置 imagePullSecrets，从 Harbor 中拉取镜像。

2，详细步骤：
一、准备环境：
1个国外的VPS，必须是国外的，配置:2h2g4M50GI，系统用rocky9版本。长期用的话，推荐磁盘大小在100G。

结构如下
VPS
 ├─ Docker
 ├─ Harbor 2.9.x+
 ├─ 域名 a.com
 └─ HTTPS 证书
 
二、步骤：
安装 Docker：
curl -fsSL https://get.docker.com |bash

安装 Docker Compose：
curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
下载 Harbor 2.9.x 版本：

wget https://github.com/goharbor/harbor/releases/download/v2.9.3/harbor-offline-installer-v2.9.3.tgz
tar xvf harbor-offline-installer-v2.9.3.tgz
cd harbor

编辑 Harbor 配置文件 harbor.yml：vim harbor.yml

修改 hostname 和其他相关配置项：
hostname: a.com  # 你的 Harbor 访问地址
ui_secret: your_ui_secret
http:
  port: 80
https:
  port: 443
  certificate: /etc/harbor/ssl/harbor.crt  # 你的证书路径
  private_key: /etc/harbor/ssl/harbor.key  # 你的私钥路径


安装 Harbor：
./install.sh


配置ssl证书：
curl https://get.acme.sh | sh
source ~/.bashrc
~/.acme.sh/acme.sh --issue -d a.com --standalone
~/.acme.sh/acme.sh --install-cert -d a.com \
  --key-file /etc/harbor/ssl/harbor.key \
  --fullchain-file /etc/harbor/ssl/harbor.crt \
  --reloadcmd "systemctl reload nginx"

启动 Harbor,使用 Docker Compose 启动 Harbor：
docker-compose up -d

检查 Harbor 是否启动成功：docker-compose ps

访问 https://a.com，确保 Harbor UI 正常。

三、Harbor 配置代理缓存

在 Harbor 中创建 Proxy Cache 项目，创建 Proxy Cache 类型的项目，按需命名：
[![Image Example](images/your-image.png)](https://raw.githubusercontent.com/ymlstudy/test/refs/heads/main/harbor-vps/h1.png)


https://raw.githubusercontent.com/ymlstudy/test/refs/heads/main/harbor-vps/h1.png

在 Harbor 中创建上面的这几个名字的项目，打开镜像代理，一一对应。
![External Image]([https://example.com/image.jpg](https://raw.githubusercontent.com/ymlstudy/test/refs/heads/main/harbor-vps/h2.png))

https://raw.githubusercontent.com/ymlstudy/test/refs/heads/main/harbor-vps/h2.png

四、Kubernetes 配置
1，配置 K8s 节点信任 Harbor 证书
每个 K8s 节点需要信任 Harbor 证书，以确保 K8s 节点能够通过 HTTPS 正常访问 Harbor。
在每台 K8s 节点上执行以下步骤：

mkdir -p /etc/containerd/certs.d/a.com
cat > /etc/containerd/certs.d/a.com/hosts.toml <<EOF
server = "https://a.com"

[host."https://a.com"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF
systemctl restart containerd

2,创建 Docker Secret
在 K8s 中创建用于从 Harbor 拉取镜像的 Docker 登录凭证：

kubectl create secret docker-registry harbor-secret \
  --docker-server=a.com \
  --docker-username=admin \
  --docker-password=your_password \
  --docker-email=admin@a.com


3,绑定 Docker Secret 到默认服务账户
将该 secret 与默认的 service account 绑定，确保所有 pod 默认可以使用该凭证拉取镜像：

kubectl patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"harbor-secret"}]}'

4，Kyverno 配置自动镜像重写

Kyverno 用于在 K8s 中自动修改镜像地址，将镜像从公共镜像仓库代理至 Harbor。
安装 Kyverno：
kubectl create -f https://raw.githubusercontent.com/kyverno/kyverno/main/docs/installation/kyverno.yaml

创建一个 Kyverno 策略来重写所有 Pod 中的镜像地址
harbor-vps/rewrite-image-all.yaml
kubectl apply -f harbor-vps/rewrite-image-all.yaml

这样每当 Pod 被创建时，Kyverno 会自动重写镜像地址。

五：验证测试
kubectl run test-pod --image=nginx:1.25 --restart=Never
kubectl get pod test-pod -o jsonpath='{.spec.containers[0].image}'

输出应该为：
a.com/dockerhub/library/nginx:1.25

kubectl get pods
所有 Pod 应该都能成功启动并拉取镜像。
