#!/bin/bash

# --- 检查文件是否存在的辅助函数 ---
check_file_exist() {
  if [ ! -f "$1" ]; then
    touch "$1"
  fi
}

# --- 配置文件创建：/etc/udev/rules.d/10-network.rules ---
echo "--- 正在创建网络 Udev 规则 ---"
if ! grep -q '00:23:12:21:d8:ae' /etc/udev/rules.d/10-network.rules; then
  cat << EOF > /etc/udev/rules.d/10-network.rules
SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="00:23:12:21:d8:ae", NAME="eth0"
EOF
  echo "✅ 规则文件 /etc/udev/rules.d/10-network.rules 创建成功。"
else
  echo "✅ 规则文件已存在，跳过创建。"
fi

# --- 配置文件创建：/etc/sysconfig/network-scripts/ifcfg-eth0 ---
echo "--- 正在创建 ifcfg-eth0 配置文件 ---"
if ! grep -q 'IPADDR=192.168.6.11' /etc/sysconfig/network-scripts/ifcfg-eth0; then
  cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
BOOTPROTO=static
NAME=eth0
DEVICE=eth0
ONBOOT=yes
IPADDR=192.168.6.11
NETMASK=255.255.255.0
GATEWAY=192.168.6.1
DNS1=192.168.6.1
EOF
  echo "✅ 网络配置文件 /etc/sysconfig/network-scripts/ifcfg-eth0 创建成功。"
else
  echo "✅ 网络配置文件已存在，跳过创建。"
fi

# --- 配置文件创建：/etc/profile 和 /etc/profile.d/env.sh ---
echo "--- 正在配置系统环境变量 ---"
if ! grep -q 'export HISTTIMEFORMAT' /etc/profile; then
  tee -a /etc/profile > /dev/null <<EOF
export HISTTIMEFORMAT="%F %T \$(whoami) "
export M2_HOME=/usr/local/maven/apache-maven-3.9.12
export MAVEN_HOME=/usr/local/maven/apache-maven-3.9.12
export JAVA_HOME=/usr/local/java/jdk-17.0.12
export PATH=\$PATH:\$JAVA_HOME/bin:\$MAVEN_HOME/bin
EOF
  echo "✅ /etc/profile 已更新。"
else
  echo "✅ /etc/profile 已包含相关环境变量，跳过。"
fi

if ! grep -q 'PS1' /etc/profile.d/env.sh; then
  tee -a /etc/profile.d/env.sh > /dev/null <<EOF
#PS1="\[\e[1;32m\][\[\e[0m\]\t \[\e[1;33m\]\u\[\e[36m\]@\h\[\e[1;31m\] \W\[\e[1;32m\]]\[\e[0m\]\$"
PS1="\[\e[1;32m\][\[\e[1;33m\]\u\[\e[36m\]@\h\[\e[1;31m\] \W\[\e[1;32m\]]\[\e[0m\]\$"
EOF
  echo "✅ /etc/profile.d/env.sh 已更新。"
else
  echo "✅ /etc/profile.d/env.sh 已包含相关内容，跳过。"
fi

# --- 配置文件创建：/root/.vimrc ---
echo "--- 正在配置 Vim ---"
if ! grep -q 'set ignorecase' /root/.vimrc; then
  tee -a /root/.vimrc > /dev/null <<EOF
set ignorecase
set cursorline
set autoindent
set paste
EOF
  echo "✅ /root/.vimrc 已更新。"
else
  echo "✅ /root/.vimrc 已包含相关设置，跳过。"
fi

# --- 安装必需的工具 ---
echo "--- 正在安装系统工具 ---"
dnf install -y vim wget curl tar zip unzip net-tools iproute traceroute nmap telnet lsof tcpdump \
  procps-ng dstat sysstat git make gcc gcc-c++ perl nodejs vim-enhanced sudo epel-release systemd \
  firewalld chrony lrzsz tree bash-completion psmisc httpd-tools glibc glibc-devel pcre pcre-devel \
  openssl openssl-devel zlib-devel libevent-devel bc systemd-devel

# --- 安装 Java 和 Maven ---
echo "--- 正在安装 Java 和 Maven ---"
if [ ! -d "/usr/local/java/jdk-17.0.12" ]; then
  wget https://download.oracle.com/java/17/archive/jdk-17.0.12_linux-x64_bin.tar.gz
  tar -xvf jdk-17.0.12_linux-x64_bin.tar.gz
  sudo mkdir -p /usr/local/java
  sudo mv jdk-17.0.12 /usr/local/java/
  rm -f jdk-17.0.12_linux-x64_bin.tar.gz
fi

if [ ! -d "/usr/local/maven/apache-maven-3.9.12" ]; then
  wget https://dlcdn.apache.org/maven/maven-3/3.9.12/binaries/apache-maven-3.9.12-bin.tar.gz
  tar -xvf apache-maven-3.9.12-bin.tar.gz
  sudo mkdir -p /usr/local/maven
  sudo mv apache-maven-3.9.12 /usr/local/maven/
  rm -f apache-maven-3.9.12-bin.tar.gz /root/anaconda-ks.cfg  /root/original-ks.cfg
fi
echo "✅ Java 和 Maven 安装完成。"

# --- 更新 GRUB 配置以禁用网络接口名称 ---
echo "--- 正在更新 GRUB 配置 ---"
if ! grep -q 'net.ifnames=0 biosdevname=0' /etc/default/grub; then
  sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 net.ifnames=0 biosdevname=0"/' /etc/default/grub
  grub2-mkconfig -o /boot/grub2/grub.cfg
  echo "✅ GRUB 配置已更新。"
else
  echo "✅ GRUB 配置已包含 net.ifnames=0 biosdevname=0，跳过。"
fi

# --- 获取并更新网络接口的 MAC 地址 ---
echo "--- 正在更新 Udev 规则的 MAC 地址 ---"
mac_address=$(ip -o link | awk '$2 != "lo:" {print $2}' | sed 's/.$//' | head -n1 | xargs -I {} ip link show {} | awk '/link\/ether/ {print $2}')
if [ -n "$mac_address" ]; then
  sed -i "s#ATTR{address}==\".*\"#ATTR{address}==\"${mac_address}\"#" /etc/udev/rules.d/10-network.rules
  #sed -i "s#ATTR{address}==\"[^\"]*\"#ATTR{address}==\"${mac_address}\"#" /etc/udev/rules.d/10-network.rules

  echo "✅ MAC 地址已更新为 ${mac_address}"
else
  echo "❌ 未找到 MAC 地址，跳过更新。"
fi

# --- 用户输入新的 IP 地址 ---
echo "--- 正在配置网络 IP 地址 ---"
read -p "Enter Your IP: " ip
if ! grep -q "IPADDR=192.168.6.${ip}" /etc/sysconfig/network-scripts/ifcfg-eth0; then
  sed -i "s#^IPADDR=.*#IPADDR=192.168.6.${ip}#g" /etc/sysconfig/network-scripts/ifcfg-eth0
  echo "✅ IP 地址已修改为 192.168.6.${ip}"
else
  echo "✅ IP 地址已经是 192.168.6.${ip}，跳过修改。"
fi

# --- 如果 SSH 密钥已存在，则跳过密钥生成步骤 ---
echo "--- 正在配置 SSH 密钥 ---"
if [ ! -f /root/.ssh/id_rsa ]; then
  echo "SSH key does not exist. Generating SSH key..."
  mkdir -p /root/.ssh
  ssh-keygen -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa -C "root@$(hostname)"
  cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
  echo "✅ SSH 密钥生成并配置成功。"
else
  echo "✅ SSH 密钥已存在，跳过生成。"
fi

# --- 下载github上的一些脚本 ---
echo "--- 正在下载github脚本 ---"
cd /root
curl -L -o  /root/k8s.zip https://raw.githubusercontent.com/ymlstudy/test/refs/heads/main/k8s_shell.zip
if [ -f /root/k8s.zip ]; then
  unzip -o /root/k8s.zip && rm -rf /root/k8s.zip
  echo "✅ 下载并解压 k8s.zip 完成。"
else
  echo "❌ 下载 k8s.zip 失败，跳过解压。"
fi

# --- 提示重启 ---
echo "--- 系统初始化完成，即将重启 ---"
echo "Rebooting after 3 seconds..."
for i in {3..1}; do
  echo "$i"
  sleep 1
done

echo "Reboot Now!"
reboot
