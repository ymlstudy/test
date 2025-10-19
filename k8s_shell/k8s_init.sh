#!/bin/bash
echo "--- 开始执行 01-common-prerequisites.sh ---"

echo "--- 1. 更新系统 ---"
sudo dnf update -y
cat  >> /etc/profile <<EOF
alias ssh='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
alias scp='scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
EOF

echo "--- 2. 禁用 SELinux ---"
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config
echo "SELinux 已禁用。请注意：为了永久生效，建议在运行完此脚本后重启系统。"

echo "--- 3. 禁用 FirewallD ---"
sudo systemctl stop firewalld
sudo systemctl disable firewalld
echo "FirewallD 已禁用。"

echo "--- 4. 禁用 Swap 分区 ---"
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
echo "Swap 已禁用。"

echo "--- 5. 添加系统资源限制,内核模块和 sysctl 参数 ---"
sudo modprobe br_netfilter
sudo modprobe overlay

cat <<EOF | sudo tee /etc/security/limits.d/99-k8s.conf
* soft nofile 65535
* hard nofile 65535
* soft nproc 65535
* hard nproc 65535
root soft nofile 65535
root hard nofile 65535
root soft nproc 65535
root hard nproc 65535
EOF

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
overlay
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sudo sysctl --system
echo "内核模块和 sysctl 参数已设置。"

echo "--- 6. 配置 hosts 文件 (可选，请手动修改) ---"
cat > /etc/hosts <<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6

192.168.6.11 h11
192.168.6.12 h12
192.168.6.13 h13
192.168.6.14 h14
192.168.6.15 h15
192.168.6.16 h16
192.168.6.17 h17
192.168.6.18 h18
192.168.6.19 h19
192.168.6.20 h20
192.168.6.21 h21
192.168.6.22 h22
192.168.6.23 h23
192.168.6.24 h24
192.168.6.25 h25
192.168.6.26 h26
192.168.6.27 h27
192.168.6.28 h28
192.168.6.29 h29
192.168.6.30 h30
EOF
echo "请在所有节点修改完成后继续。"

# 07 所有节点安装ipvsadm
dnf install ipvsadm ipset sysstat conntrack libseccomp dnf-utils device-mapper-persistent-data lvm2  -y

# 内核参数优化，所有节点配置
cat > /etc/sysctl.d/k8s.conf <<EOF
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
fs.may_detach_mounts = 1
fs.file-max=1000000
vm.swappiness=0
vm.overcommit_memory=1
vm.panic_on_oom=0
vm.max_map_count=262144
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl =15
net.ipv4.tcp_max_tw_buckets = 36000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_max_orphans = 327680
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.ip_conntrack_max = 65536
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_timestamps = 0
net.core.somaxconn = 16384
net.netfilter.nf_conntrack_max=2097152
kernel.pid_max=4194303
EOF

内核模块开机挂载
sudo bash -c 'cat > /etc/modules-load.d/modules.conf <<EOF
ip_vs
ip_vs_lc
ip_vs_lblc
ip_vs_lblcr
ip_vs_rr
ip_vs_wrr
ip_vs_sh
ip_vs_dh
ip_vs_fo
ip_vs_nq
ip_vs_sed
ip_vs_ftp
ip_vs_sh
ip_tables
ip_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip
xt_set
br_netfilter
nf_conntrack
overlay
EOF
' && sysctl --system && sysctl -p

echo "--- 01-common-prerequisites.sh 执行完毕。强烈建议此时重启所有节点，以确保所有配置永久生效。---"


echo "--- 开始执行 02-common-containerd.sh ---"

echo "--- 1. 添加 Docker 官方仓库 ---"
sudo dnf install -y dnf-utils
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
echo "Docker 仓库添加完成。"

echo "--- 2. 安装 Containerd ---"
sudo dnf install -y containerd.io
echo "Containerd 安装完成。"

echo "--- 3. 生成默认 Containerd 配置并修改 ---"
sudo mkdir -p /etc/containerd
# 备份旧配置，如果存在
if [ -f "/etc/containerd/config.toml" ]; then
    sudo mv /etc/containerd/config.toml /etc/containerd/config.toml.bak
    echo "已备份 /etc/containerd/config.toml 为 /etc/containerd/config.toml.bak"
fi
sudo containerd config default | sudo tee /etc/containerd/config.toml

# 使用 sed 修改 SystemdCgroup 和添加镜像加速器
echo "修改 Containerd 配置：SystemdCgroup 和镜像加速器"
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
# 添加镜像加速器配置
# 请将 registry.aliyuncs.com/google_containers 替换为你实际使用的镜像加速器地址
sudo sed -i '/\[plugins\."io.containerd.grpc.v1.cri"\.registry\.mirrors\]/a \
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."registry.k8s.io"]\
          endpoint = ["https://registry.aliyuncs.com/google_containers"]' /etc/containerd/config.toml
		  


sed -i '/OOMScoreAdjust/a LimitNOFILE=65535:65535' /usr/lib/systemd/system/containerd.service
echo "Containerd 配置修改完成。"


echo "--- 5. 启动并设置 Containerd 开机自启 ---"
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
echo "Containerd 服务已启动并设置开机自启。"

echo "安装containerd客户端工具nerdctl"
wget https://github.com/containerd/nerdctl/releases/download/v1.7.2/nerdctl-1.7.2-linux-amd64.tar.gz && tar xvf nerdctl-1.7.2-linux-amd64.tar.gz -C /usr/local/bin/ &&rm -rf nerdctl-1.7.2-linux-amd64.tar.gz && nerdctl version

echo "创建nerdctl配置文件"
mkdir -p /etc/nerdctl && cat > /etc/nerdctl/nerdctl.toml <<EOF
namespace = "k8s.io"
debug = false
debug_full = false
insecure_registry = true
EOF

echo "--- 02-common-containerd.sh 执行完毕。---"

echo "--- 1. 添加 Kubernetes YUM 仓库 ---"
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.28/rpm/repodata/repomd.xml.key
EOF
echo "Kubernetes 仓库添加完成。"

echo "--- 2. 安装 kubeadm, kubelet, kubectl ---"
sudo dnf install -y kubelet kubeadm kubectl

sed -i '/RestartSec/a LimitNOFILE=65535:65535' /usr/lib/systemd/system/kubelet.service
echo "kubeadm, kubelet, kubectl 安装完成。"

echo "--- 3. 设置 kubelet 开机自启 ---"
sudo systemctl enable --now kubelet
systemctl daemon-reload && systemctl restart kubelet.service containerd.service
echo "kubelet 服务已启动并设置开机自启。"
echo "--- 03-common-kube-tools.sh 执行完毕。---"

echo "开始重启,倒计时5s"

for i in {5..1}; do
  echo "$i"
  sleep 1
done
 
echo "Reboot Now！"
reboot
