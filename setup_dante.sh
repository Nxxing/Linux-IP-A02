#!/bin/bash

# 自定義參數
DANTE_CONF="/opt/dante/etc/danted.conf"
DANTE_LOG="/opt/dante/log/dante.log"
DANTE_BIN="/opt/dante/sbin/sockd"
SYSTEMD_SERVICE="/etc/systemd/system/dante.service"

# 自定義帳號和密碼
DANTE_USER="proxyuser"  # 修改為您想要的帳號
DANTE_PASS="proxypass"  # 修改為您想要的密碼

# 確認網卡名稱和可用的 IP 地址
NET_IF="ens5"
IPV4_ADDR=$(ip -4 addr show "$NET_IF" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
IPV6_ADDR=$(ip -6 addr show "$NET_IF" | grep "inet6 " | grep "global" | awk '{print $2}' | cut -d/ -f1)

# 檢查必要的目錄
mkdir -p /opt/dante/log

# 添加系統帳號驗證
echo "$DANTE_USER $DANTE_PASS" > /etc/dante.passwd
chmod 600 /etc/dante.passwd

# 配置 Dante
cat > "$DANTE_CONF" <<EOL
logoutput: $DANTE_LOG
logoutput: stderr

# 綁定網卡和端口
internal: $NET_IF port = 3128
external: $NET_IF

# 認證方式
socksmethod: username
user.privileged: root
user.unprivileged: nobody

# 訪問控制規則 (IPv4 和 IPv6)
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
    username: $DANTE_USER
}
socks pass {
    from: ::/0 to: ::/0
    log: connect error
    protocol: tcp udp
    username: $DANTE_USER
}
EOL

# 配置 systemd 服務
cat > "$SYSTEMD_SERVICE" <<EOL
[Unit]
Description=Dante proxy service
After=network.target

[Service]
ExecStart=$DANTE_BIN -f $DANTE_CONF
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# 重新加載 systemd，啟動服務
systemctl daemon-reload
systemctl enable dante
systemctl restart dante

# 確認服務狀態
systemctl status dante
