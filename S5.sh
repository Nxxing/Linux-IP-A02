#!/bin/bash

# 配置參數
PORT=3128               # 代理端口
NET_IF="ens5"           # 網卡名稱 (根據實際情況修改)
LOGFILE="/opt/dante/log/dante.log"  # 日誌文件
CONFIG_FILE="/opt/dante/etc/danted.conf"
SERVICE_FILE="/etc/systemd/system/dante.service"
AUTH_FILE="/opt/dante/etc/sockd.passwd"
UNPRIVILEGED_USER="nobody"  # 非特權用戶
DEFAULT_USER="user"         # 預設用戶名
DEFAULT_PASS="X3KVTD6tsFkTtuf5"  # 預設密碼

# 確保腳本以 root 身份運行
if [[ $EUID -ne 0 ]]; then
    echo "請以 root 權限運行此腳本"
    exit 1
fi

# 確認非特權用戶存在
if ! id -u "$UNPRIVILEGED_USER" >/dev/null 2>&1; then
    echo "創建非特權用戶 $UNPRIVILEGED_USER..."
    useradd -r -s /sbin/nologin "$UNPRIVILEGED_USER"
fi

# 停止 Dante 服務（如服務正在運行）
echo "停止 Dante 服務..."
systemctl stop dante 2>/dev/null || echo "Dante 服務未在運行"

# 檢測私有 IPv4 和 IPv6 地址
IPV4_ADDR=$(ip -4 addr show "$NET_IF" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
IPV6_ADDR=$(ip -6 addr show "$NET_IF" | grep "inet6 " | grep "global" | awk '{print $2}' | cut -d/ -f1)

if [[ -z "$IPV4_ADDR" || -z "$IPV6_ADDR" ]]; then
    echo "未能檢測到 IPv4 或 IPv6 地址，請確認網卡 $NET_IF 配置正確。"
    exit 1
fi

# 創建配置文件目錄和日誌目錄
mkdir -p /opt/dante/etc
mkdir -p /opt/dante/log

# 配置帳密文件
echo "配置帳密文件..."
cat > "$AUTH_FILE" <<EOL
$DEFAULT_USER: $DEFAULT_PASS
EOL
chmod 600 "$AUTH_FILE"

# 配置 danted.conf 文件
echo "生成 danted.conf 配置文件..."
cat > "$CONFIG_FILE" <<EOL
logoutput: $LOGFILE
logoutput: stderr

# 綁定網卡和端口
internal: $NET_IF port = $PORT
internal: :: port = $PORT
external: $NET_IF

socksmethod: username
user.privileged: root
user.unprivileged: $UNPRIVILEGED_USER

# 用戶驗證文件
userlist: $AUTH_FILE

# 訪問控制規則
client pass {
    from: 0.0.0.0/0 port 1-65535 to: 0.0.0.0/0
    log: connect error
}
client pass {
    from: ::/0 port 1-65535 to: ::/0
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

# 配置 systemd 服務文件
echo "配置 systemd 服務..."
cat > "$SERVICE_FILE" <<EOL
[Unit]
Description=Dante SOCKS proxy
After=network.target

[Service]
ExecStart=/opt/dante/sbin/sockd -f $CONFIG_FILE
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# 開放防火牆規則
echo "配置防火牆..."
iptables -A INPUT -p tcp --dport $PORT -j ACCEPT
ip6tables -A INPUT -p tcp --dport $PORT -j ACCEPT

# 重新加載 systemd 配置
echo "重新加載 systemd 配置..."
systemctl daemon-reload

# 啟動 Dante 服務
echo "啟動 Dante 服務..."
systemctl enable dante
systemctl start dante

# 測試代理
echo "測試代理..."
echo "測試 IPv4 代理..."
curl -x socks5h://$DEFAULT_USER:$DEFAULT_PASS@${IPV4_ADDR}:${PORT} -4 http://ipv4.icanhazip.com
echo "測試 IPv6 代理..."
curl -x socks5h://$DEFAULT_USER:$DEFAULT_PASS@[${IPV6_ADDR}]:${PORT} -6 http://ipv6.icanhazip.com

# 顯示完成信息
echo "Dante 配置完成，代理信息如下："
echo "--------------------------------"
echo "IPv4 地址: $IPV4_ADDR"
echo "IPv6 地址: $IPV6_ADDR"
echo "端口: $PORT"
echo "用戶名: $DEFAULT_USER"
echo "密碼: $DEFAULT_PASS"
echo "--------------------------------"
echo "日誌文件: $LOGFILE"
echo "如需排錯，請檢查日誌文件。"
