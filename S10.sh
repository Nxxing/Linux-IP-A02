#!/bin/bash

# 一鍵配置 Dante Server
echo "配置 Dante Server 開始..."

# 配置文件路徑
CONF_PATH="/etc/danted.conf"  # 修改為默認路徑，根據實際情況調整

# 創建 Dante 配置
echo "正在生成配置文件..."
cat <<EOF >"$CONF_PATH"
logoutput: syslog
internal: 0.0.0.0 port = 3128   # IPv4 支持
internal: :: port = 3128       # IPv6 支持
external: 0.0.0.0              # IPv4 外部地址
external: ::                   # IPv6 外部地址

method: username

user.privileged: proxy
user.notprivileged: nobody
user.libwrap: nobody

# 訪問控制規則
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    from: ::/0 to: ::/0
    log: connect
}

pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    from: ::/0 to: ::/0
    protocol: tcp udp
    log: connect
}
EOF

echo "配置文件已生成：$CONF_PATH"

# 添加用戶（如果未存在）
USERNAME="user"
PASSWORD="X3KVTD6tsFkTtuf5"

if id "$USERNAME" &>/dev/null; then
  echo "用戶 $USERNAME 已存在"
else
  echo "創建用戶 $USERNAME..."
  useradd -m "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd
  echo "用戶 $USERNAME 已創建"
fi

# 確保 'proxy' 用戶存在
PROXY_USER="proxy"
if id "$PROXY_USER" &>/dev/null; then
  echo "用戶 $PROXY_USER 已存在"
else
  echo "創建用戶 $PROXY_USER..."
  useradd -r -s /usr/sbin/nologin "$PROXY_USER"
  echo "用戶 $PROXY_USER 已創建"
fi

# 啟用並啟動 Dante 服務
echo "啟動 Dante..."
systemctl restart danted
systemctl enable danted

# 檢查 Dante 服務狀態
if systemctl status danted | grep -q "active (running)"; then
  echo "Dante 服務已啟動成功，端口：3128"
else
  echo "Dante 啟動失敗，請檢查配置或日誌"
  exit 1
fi

# 設置防火牆規則
echo "設置防火牆規則..."
if command -v ufw &>/dev/null; then
  sudo ufw allow 3128/tcp
  sudo ufw allow 3128/udp
elif command -v firewall-cmd &>/dev/null; then
  sudo firewall-cmd --permanent --add-port=3128/tcp
  sudo firewall-cmd --permanent --add-port=3128/udp
  sudo firewall-cmd --reload
else
  sudo iptables -I INPUT -p tcp --dport 3128 -j ACCEPT
  sudo iptables -I INPUT -p udp --dport 3128 -j ACCEPT

  sudo ip6tables -I INPUT -p tcp --dport 3128 -j ACCEPT
  sudo ip6tables -I INPUT -p udp --dport 3128 -j ACCEPT
fi

echo "防火牆規則已設置"

echo "請使用以下用戶名和密碼測試代理服務："
echo "地址: <伺服器IP>:3128"
echo "用戶名: $USERNAME"
echo "密碼: $PASSWORD"

echo "配置完成！"
