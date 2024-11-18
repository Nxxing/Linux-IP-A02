#!/bin/bash

# 脚本参数
PORT=3128             # 代理监听端口
USER="proxyuser"      # 代理用户名
PASS="proxypass"      # 代理密码
NET_IF="ens5"         # 使用的网络接口 (根据实际调整)

# 检查权限
if [[ $EUID -ne 0 ]]; then
    echo "请以 root 身份运行脚本"
    exit 1
fi

# 更新并安装必要依赖
echo "更新系统并安装依赖..."
if [ -f /etc/debian_version ]; then
    apt update && apt install -y gcc make libpam0g-dev
elif [ -f /etc/redhat-release ]; then
    yum install -y gcc make pam-devel
else
    echo "不支持的系统版本，请手动安装依赖。"
    exit 1
fi

# 下载并安装 Dante
echo "下载并安装 Dante..."
DANTE_URL="http://www.inet.no/dante/files/dante-1.4.3.tar.gz"
curl -O "$DANTE_URL"
tar xzf dante-1.4.3.tar.gz
cd dante-1.4.3 || exit
./configure --prefix=/opt/dante
make && make install

# 创建配置文件目录
mkdir -p /opt/dante/etc
mkdir -p /opt/dante/log

# 检测私有 IPv4 和 IPv6 地址
IPV4_ADDR=$(ip -4 addr show "$NET_IF" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
IPV6_ADDR=$(ip -6 addr show "$NET_IF" | grep "inet6 " | grep "global" | awk '{print $2}' | cut -d/ -f1)

if [[ -z "$IPV4_ADDR" || -z "$IPV6_ADDR" ]]; then
    echo "无法检测私有 IPv4 或 IPv6 地址，请检查网络接口 $NET_IF 是否正确。"
    exit 1
fi

# 创建认证文件
echo "配置认证信息..."
echo "$USER $PASS" > /etc/dante.passwd
chmod 600 /etc/dante.passwd

# 生成 danted.conf
echo "生成 danted.conf 文件..."
cat > /opt/dante/etc/danted.conf <<EOL
logoutput: /opt/dante/log/dante.log
internal: $NET_IF port = $PORT
external: $NET_IF

socksmethod: username
user.privileged: root
user.unprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
}
client pass {
    from: ::/0 to: ::/0
    log: connect error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect error
    protocol: tcp udp
}
socks pass {
    from: ::/0 to: ::/0
    log: connect error
    protocol: tcp udp
}
EOL

# 创建 systemd 服务文件
echo "配置系统服务..."
cat > /etc/systemd/system/dante.service <<EOL
[Unit]
Description=Dante SOCKS proxy
After=network.target

[Service]
ExecStart=/opt/dante/sbin/sockd -f /opt/dante/etc/danted.conf
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# 设置权限并启动服务
echo "启动 Dante 服务..."
systemctl daemon-reload
systemctl enable dante
systemctl start dante

# 验证服务状态
systemctl status dante
echo "Dante 已完成安装，代理信息如下："
echo "--------------------------------"
echo "IPv4 地址: $IPV4_ADDR"
echo "IPv6 地址: $IPV6_ADDR"
echo "端口: $PORT"
echo "用户名: $USER"
echo "密码: $PASS"
echo "--------------------------------"
