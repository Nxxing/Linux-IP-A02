#!/bin/bash

# 配置參數
PORT=3128               # 代理端口
USER="proxyuser"        # 代理用戶名
PASS="proxypass"        # 代理密碼
NET_IF="ens5"           # 網卡名稱 (根據實際情況修改)

# 確保腳本以 root 身份運行
if [[ $EUID -ne 0 ]]; then
    echo "請以 root 權限運行此腳本"
    exit 1
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

# 創建配置目錄和日誌目錄
mkdir -p /opt/dante/etc
mkdir -p /opt/dante/log

# 創建用戶認證文件
echo "創建用戶認證信息..."
echo "$USER $PASS" > /etc/dante.passwd
chmod 600 /etc/dante.passwd

# 配置 danted.conf 文件
echo "生成 danted.conf 配置文件..."
cat > /opt/dante/etc/danted.conf <<EOL
logoutput: /opt/dante/log/dante.log
logoutput: stderr

# 綁定網卡和端口
internal: $NET_IF port = $PORT
external: $NET_IF

socksmethod: username
user.privileged: root
user.unprivileged: nobody

# 訪問控制規則
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
    username: $USER
}
socks pass {
    from: ::/0 to: ::/0
    log: connect error
    protocol: tcp udp
    username: $USER
}
EOL

# 配置 systemd 服務文件
echo "配置 systemd 服務..."
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

# 重新加載 systemd 配置
echo "重新加載 systemd 配置..."
systemctl daemon-reload

# 啟動 Dante 服務
echo "啟動 Dante 服務..."
systemctl enable dante
systemctl start dante

# 驗證服務狀態
echo "驗證 Dante 服務狀態..."
systemctl status dante

# 提供配置信息
echo "Dante 配置完成，代理信息如下："
echo "--------------------------------"
echo "IPv4 地址: $IPV4_ADDR"
echo "IPv6 地址: $IPV6_ADDR"
echo "端口: $PORT"
echo "用戶名: $USER"
echo "密碼: $PASS"
echo "--------------------------------"
