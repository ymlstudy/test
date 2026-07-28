#!/bin/bash

# 1. 检查 root 权限
if [ "$EUID" -ne 0 ]; then
    echo "请使用 root 权限运行此脚本！"
    exit 1
fi

echo "========================================"
echo "    CentOS7 一键网络配置与系统初始化"
echo "========================================"

# 2. 交互输入最后的 IP 尾数
read -p "请输入 IP 地址的最后一段数字 (例如输入 11 代表 192.168.6.11): " LAST_NUM

# 检查输入是否合法 (2-254)
if [[ -z "$LAST_NUM" || ! "$LAST_NUM" =~ ^[0-9]+$ || "$LAST_NUM" -lt 2 || "$LAST_NUM" -gt 254 ]]; then
    echo "错误: 输入不合法！请输入 2 到 254 之间的数字。"
    exit 1
fi

IPADDR="192.168.6.${LAST_NUM}"
CFG_FILE="/etc/sysconfig/network-scripts/ifcfg-eth0"
LOG_FILE="/var/log/network_init.log"

# 3. 自动获取当前正在联网的网卡名字
CURRENT_DEV=$(ip -o link show | awk -F': ' '{print $2}' | grep -v lo | head -n1)
if [ -z "$CURRENT_DEV" ]; then
    echo "错误: 未检测到有效网卡！"
    exit 1
fi

echo "[INFO] 1. 正在写入网络静态配置文件..."
if [ -f "$CFG_FILE" ]; then
    cp "$CFG_FILE" "${CFG_FILE}.bak"
fi

cat > "$CFG_FILE" <<EOF
BOOTPROTO=static
NAME=eth0
DEVICE=eth0
ONBOOT=yes
IPADDR=${IPADDR}
NETMASK=255.255.255.0
GATEWAY=192.168.6.1
DNS1=192.168.6.1
EOF

echo "[INFO] 2. 正在写入自定义环境变量与别名..."
cat >/etc/profile.d/env.sh <<'EOF'
export HISTSIZE=100000
export HISTFILESIZE=100000
export HISTTIMEFORMAT="%F %T $(whoami) "
export HISTCONTROL=ignoredups
export PROMPT_COMMAND="history -a"

export JAVA_HOME=/usr/local/java/jdk-17.0.12
export M2_HOME=/usr/local/maven/apache-maven-3.9.16
export MAVEN_HOME=/usr/local/maven/apache-maven-3.9.16
export PATH=$PATH:$JAVA_HOME/bin:$MAVEN_HOME/bin

alias ssh='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
alias scp='scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
alias ll='ls -alh'
alias la='ls -A'
alias l='ls -CF'
alias vi='vim'

PS1="\[\e[1;32m\][\[\e[0m\]\t \[\e[1;33m\]\u\[\e[36m\]@\h\[\e[1;31m\] \W\[\e[1;32m\]]\[\e[0m\]\\$ "
EOF

echo "[INFO] 3. 正在写入 Vim 优化配置..."
cat > ~/.vimrc <<'EOF'
syntax on
set number
set ignorecase
set cursorline
set autoindent
set expandtab
set tabstop=4
set shiftwidth=4
set paste
EOF

echo "[INFO] 4. 正在写入安全限制与内核参数..."
cat >/etc/security/limits.d/99-custom.conf <<'EOF'
* soft nofile 102400
* hard nofile 102400
* soft nproc 65535
* hard nproc 65535
root soft nofile 102400
root hard nofile 102400
EOF

cat >/etc/sysctl.d/99-custom.conf <<'EOF'
fs.file-max=2097152
vm.swappiness=10
net.ipv4.ip_forward=1
net.core.somaxconn=65535
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.ip_local_port_range=1024 65000
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF

echo "[INFO] 5. 正在配置系统关闭 SELinux 与 Swap..."
sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config
sed -ri '/swap/s/^/#/' /etc/fstab

echo "[INFO] 6. 正在修改 GRUB 引导参数..."
if ! grep -q net.ifnames=0 /etc/default/grub; then
    sed -i 's/rhgb quiet/rhgb quiet net.ifnames=0 biosdevname=0/' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg
fi

echo "------------------------------------------------"
echo "[OK] 所有本地静态配置文件已准备就绪！"
echo "[警告] 核心安装与网络切换即将切入后台托管运行。"
echo "[提示] 你的当前 SSH 连接将在 1 秒后强制断开！"
echo "[提示] 请在 5 秒后用新 IP [192.168.6.${LAST_NUM}] 重新连入系统，"
echo "       并通过命令: tail -f ${LOG_FILE} 查看后续的下载安装进度。"
echo "------------------------------------------------"

# =========================================================
# 核心托管：把换 IP、换源、下载 Java/Maven 全套扔进后台死磕
# =========================================================
nohup bash -c "
    echo '=== [后台] 开始动态切换网络 ==='
    ip addr flush dev ${CURRENT_DEV}
    ip addr add ${IPADDR}/24 dev ${CURRENT_DEV}
    ip link set dev ${CURRENT_DEV} up
    ip route add default via 192.168.6.1 dev ${CURRENT_DEV} onlink 2>/dev/null || true
    echo 'nameserver 192.168.6.1' > /etc/resolv.conf
    
    if [ '${CURRENT_DEV}' = 'eth0' ]; then
        systemctl restart network
    fi
    
    echo '=== [后台] 网络已切断并重构，等待 3 秒网络稳定 ==='
    sleep 3
    
    echo '=== [后台] 激活内核参数与基础服务调整 ==='
    modprobe br_netfilter || true
    sysctl --system || true
    setenforce 0 || true
    systemctl disable --now firewalld || true
    systemctl enable --now chronyd || true
    swapoff -a
    
    echo '=== [后台] 优化 SSH 连接速度 ==='
    sed -i 's/^#UseDNS yes/UseDNS no/' /etc/ssh/sshd_config || true
    grep -q '^GSSAPIAuthentication no' /etc/ssh/sshd_config || echo 'GSSAPIAuthentication no' >> /etc/ssh/sshd_config
    systemctl restart sshd || true
    
    echo '=== [后台] 开始更换阿里云 Yum 源 ==='
    curl -L -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
    sed -i 's|mirrors.cloud.aliyuncs.com|mirrors.aliyun.com|g' /etc/yum.repos.d/CentOS-Base.repo
    yum clean all
    yum makecache
    
    echo '=== [后台] 开始批量安装基础工具包（耗时较长） ==='
    yum install -y vim vim-enhanced wget curl tar zip unzip net-tools iproute traceroute nmap telnet lsof tcpdump iotop procps-ng dstat sysstat git make gcc gcc-c++ perl python3 nodejs sudo epel-release systemd firewalld chrony lrzsz tree bash-completion psmisc httpd-tools glibc glibc-devel pcre pcre-devel openssl openssl-devel zlib-devel libevent-devel bc systemd-devel
    
    echo '=== [后台] 校对系统时区 ==='
    timedatectl set-timezone Asia/Shanghai || true
    
    echo '=== [后台] 开始下载并部署开发环境 ==='
    mkdir -p /usr/local/src /usr/local/java /usr/local/maven
    cd /usr/local/src
    
    echo '--- 下载并解压 JDK 17 ---'
    wget -c https://download.oracle.com/java/17/archive/jdk-17.0.12_linux-x64_bin.tar.gz
    tar -xf jdk-17.0.12_linux-x64_bin.tar.gz
    mv -f jdk-17.0.12 /usr/local/java/
    
    echo '--- 下载并解压 Maven 3.9.16 ---'
    wget -c https://dlcdn.apache.org/maven/maven-3/3.9.16/binaries/apache-maven-3.9.16-bin.tar.gz
    tar -xf apache-maven-3.9.16-bin.tar.gz
    mv -f apache-maven-3.9.16 /usr/local/maven/
    
    echo '=== [后台] 写入全局 Git 配置 ==='
    git config --global color.ui auto || true
    
    echo '=== [后台] 验证安装环境状态 ==='
    export JAVA_HOME=/usr/local/java/jdk-17.0.12
    export M2_HOME=/usr/local/maven/apache-maven-3.9.16
    export PATH=\$PATH:\$JAVA_HOME/bin:\$M2_HOME/bin
    java -version
    mvn -version
    
    echo '========================================'
    echo '   CentOS7 全套系统初始化成功完毕！'
    echo '   提示: 强烈建议您现在重启一次系统 (reboot)'
    echo '========================================'
" > "$LOG_FILE" 2>&1 &

# 留给后台1秒钟启动时间，前台优雅退出断开连接
sleep 1
exit 0