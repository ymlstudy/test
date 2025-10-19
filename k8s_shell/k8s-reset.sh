#!/bin/bash
echo "--- 正在执行 Kubernetes 清理，以准备重新初始化 ---"

echo "1. 清理 kubelet 和 Kubernetes 配置目录..."
sudo rm -rf /var/lib/kubelet/*
sudo rm -rf /etc/kubernetes/

echo "2. 清理 CNI 网络配置目录..."
sudo rm -rf /etc/cni/net.d/*
sudo rm -rf /var/lib/cni/

echo "3. 清理用户 kubeconfig 文件..."
sudo rm -rf $HOME/.kube

echo "4. 清理容器运行时数据目录 (将删除所有镜像和容器数据)..."
# 请根据你的实际配置选择正确的目录
sudo rm -rf /var/lib/containerd/* || true
sudo rm -rf /var/run/containerd/ || true
sudo rm -rf /var/lib/etcd/ || true
sudo rm -rf /var/lib/docker/* || true
sudo rm -rf /mnt/usb_storage/docker-data/* || true

echo "5. 清理 iptables 规则..."
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t raw -F && sudo iptables -t mangle -F
sudo iptables -X
sudo iptables -Z

echo "--- Kubernetes 清理完成，倒计时5S重启。 ---"
for i in {5..1}; do
  echo "$i"
  sleep 1
done
echo "Reboot Now！"
reboot