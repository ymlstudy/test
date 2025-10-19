#!/bin/bash
echo "--- 1. 初始化 Kubernetes Master 节点 ---"
# 请将 --apiserver-advertise-address 替换为你的 Master 节点的实际 IP
MASTER_IP="192.168.6.11"
POD_NETWORK_CIDR="10.244.0.0/16" # Flannel 默认使用这个 CIDR
SERVICE_CIDR="10.96.0.0/12"
K8S_VERSION="v1.28.15"
IMAGE_REPO="registry.aliyuncs.com/google_containers"
CONTROL_PLANE_ENDPOINT="h11" # 通常是Master节点的主机名或负载均衡VIP

sudo kubeadm init \
--apiserver-advertise-address="${MASTER_IP}" \
--pod-network-cidr="${POD_NETWORK_CIDR}" \
--service-cidr="${SERVICE_CIDR}" \
--kubernetes-version="${K8S_VERSION}" \
--image-repository "${IMAGE_REPO}" \
--upload-certs \
--control-plane-endpoint="${CONTROL_PLANE_ENDPOINT}"

if [ $? -eq 0 ]; then
    echo "--- 2. 配置 kubectl 访问集群 ---"
    mkdir -p $HOME/.kube
    sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config
    export KUBECONFIG=$HOME/.kube/config
    echo "export KUBECONFIG=$HOME/.kube/config" >> ~/.bashrc
    export KUBECONFIG=/etc/kubernetes/admin.conf
    echo "source <(kubectl completion bash)" >> ~/.bashrc && echo "source <(kubeadm completion bash)" >> ~/.bashrc
    cat  >> /root/.bashrc <<EOF
alias k=kubectl
complete -F __start_kubectl k
EOF
    source ~/.bashrc
    echo "kubectl 配置完成。请在新开的终端中执行 'kubectl get nodes' 验证。"

    echo "--- 3. 重要提示：保存 Worker 节点加入命令 ---"
    echo "请务必复制以下 kubeadm join 命令，用于 Worker 节点加入集群："
    JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)
    # 使用 echo -e 和 ANSI 转义码将输出变为红色
    # \e[31m 是红色代码，\e[0m 是重置颜色代码
    echo -e "\e[31m${JOIN_COMMAND}\e[0m"    
    echo "复制后请保存到安全位置！！！"
else
    echo "kubeadm init 失败，请检查日志并根据错误信息进行排查。"
    echo "查看 kubelet 日志: journalctl -xeu kubelet"
    echo "查看 containerd 日志: journalctl -xeu containerd"
fi

echo "Master 节点初始化脚本执行完毕。"


sleep 5

echo "--- 部署 Flannel 网络插件 (Master 节点) ---"

# 确保 kubectl 已配置
if ! command -v kubectl &> /dev/null; then
    echo "kubectl 命令未找到或未配置。请先执行 Master 节点初始化脚本中的 kubectl 配置步骤。"
    exit 1
fi
if ! kubectl cluster-info &> /dev/null; then
    echo "kubectl 无法连接到 Kubernetes API Server。请确保 API Server 已启动并运行。"
    echo "尝试查看: kubectl get pods -n kube-system -o wide"
    exit 1
fi

FLANNEL_YAML_URL="https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml"
FLANNEL_YAML_FILE="kube-flannel.yml"

echo "下载 Flannel 部署文件..."
# 使用代理下载，如果需要的话
if [ -n "${HTTP_PROXY}" ]; then
    wget -e use_proxy=yes -e http_proxy=${HTTP_PROXY} ${FLANNEL_YAML_URL} -O ${FLANNEL_YAML_FILE}
else
    wget ${FLANNEL_YAML_URL} -O ${FLANNEL_YAML_FILE}
fi

if [ $? -eq 0 ]; then
    echo "Flannel 部署文件下载成功：${FLANNEL_YAML_FILE}"
    echo "开始部署 Flannel..."
    kubectl apply -f "${FLANNEL_YAML_FILE}"
    if [ $? -eq 0 ]; then
        echo "Flannel 部署命令已发送。请等待 Pods 启动。"
        echo "查看 Flannel Pods 状态: kubectl get pods -n kube-flannel -o wide --watch"
        echo "等待所有节点状态变为 Ready: kubectl get nodes"
    else
        echo "Flannel 部署失败，请检查 kubectl 输出。"
    fi
else
    echo "Flannel 部署文件下载失败。请检查网络连接或手动下载并传输文件。"
fi

echo "Flannel 部署脚本执行完毕。"

sleep 5

echo "--- 开始修改 kube-proxy ConfigMap 为 IPVS 模式 ---"

# 确保 kubectl 可用
if ! command -v kubectl &> /dev/null; then
    echo "错误：kubectl 命令未找到。请确保 Kubernetes 集群已成功初始化，并且 kubectl 已正确配置。"
    exit 1
fi

# 确保 kube-proxy ConfigMap 存在
if ! kubectl get configmap kube-proxy -n kube-system &> /dev/null; then
    echo "错误：kube-proxy ConfigMap 不存在。请确保 Kubernetes 控制平面已正常启动。"
    exit 1
fi

# 1. 获取 kube-proxy ConfigMap 的 YAML 内容，并保存到临时文件
TEMP_CONFIGMAP_FILE="/tmp/kube-proxy-configmap-$(date +%s).yaml"
echo "获取 kube-proxy ConfigMap 到临时文件: ${TEMP_CONFIGMAP_FILE}"
kubectl get configmap kube-proxy -n kube-system -o yaml > "${TEMP_CONFIGMAP_FILE}"

# 2. 使用 sed 修改 mode 值为 "ipvs"
# 这个 sed 命令会找到 'mode:' 所在的行，并将其值改为 "ipvs"。
# 它会匹配 'mode: "任意值"' 或 'mode: ' (空值)。
# `\(\s*\)` 捕获行首的空白，`\1` 将其重新插入以保持缩进。
echo "在临时文件中修改 'mode' 值为 'ipvs'..."
sed -i -E 's/^(\s*)mode:\s*".*"/\1mode: "ipvs"/' "${TEMP_CONFIGMAP_FILE}"
sed -i -E 's/^(\s*)mode:\s*$/\1mode: "ipvs"/' "${TEMP_CONFIGMAP_FILE}" # 处理 mode: 后面没有引号的情况

# 3. 应用修改后的 ConfigMap
echo "应用修改后的 kube-proxy ConfigMap..."
kubectl apply -f "${TEMP_CONFIGMAP_FILE}"

if [ $? -eq 0 ]; then
    echo "kube-proxy ConfigMap 已成功修改为 IPVS 模式。"
    echo "--- 4. 删除所有 kube-proxy Pods 以使其重建 (激活 IPVS 模式) ---"
    # 删除所有 kube-proxy Pods，Kubernetes 会自动重建它们
    kubectl delete pod -l k8s-app=kube-proxy -n kube-system
    if [ $? -eq 0 ]; then
        echo "kube-proxy Pods 删除成功，系统将自动重建。请等待 Pods 启动。"
        echo "查看 kube-proxy Pods 状态: kubectl get pods -n kube-system -l k8s-app=kube-proxy --watch"
    else
        echo "删除 kube-proxy Pods 失败，请手动检查。"
    fi
else
    echo "修改 kube-proxy ConfigMap 失败，请检查错误信息。"
fi

# 5. 清理临时文件
echo "清理临时文件..."
rm "${TEMP_CONFIGMAP_FILE}"

echo "--- kube-proxy IPVS 模式配置脚本执行完毕。---"

kubectl get -n kube-system configmap kube-proxy -o yaml | grep mode
sleep 10
echo "验证ipvs是否可用"
ipvsadm -Ln

echo "--- 重要提示：保存 Worker 节点加入命令 ---"
echo "请务必复制以下 kubeadm join 命令，用于 Worker 节点加入集群："
JOIN_COMMAND=$(sudo kubeadm token create --print-join-command)
# 使用 echo -e 和 ANSI 转义码将输出变为红色
# \e[31m 是红色代码，\e[0m 是重置颜色代码
echo -e "\e[31m${JOIN_COMMAND}\e[0m"    
echo "复制后请保存到安全位置！！！"