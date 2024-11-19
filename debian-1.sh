#!/bin/bash

# 一鍵配置 XRAY Server 適用於 Debian
echo "開始配置 XRAY 代理服務器 (Debian)..."

# 檢查是否以 root 身份運行
if [ "$EUID" -ne 0 ]; then
  echo "請以 root 身份運行此腳本。"
  exit 1
fi

# 更新套件列表
echo "更新套件列表..."
apt update -y
if [ $? -ne 0 ]; then
  echo "套件列表更新失敗。"
  exit 1
fi

# 安裝必要的依賴包
echo "安裝必要的依賴包..."
apt install -y wget unzip ufw
if [ $? -ne 0 ]; then
  echo "安裝依賴包失敗。"
  exit 1
fi

# 定義 XRAY 的版本
XRAY_VERSION="1.8.3"  # 請根據官方最新版本進行更新

# 下載 XRAY
echo "下載 XRAY..."
wget https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-linux-64.zip -O /tmp/Xray-linux-64.zip
if [ $? -ne 0 ]; then
  echo "下載 XRAY 失敗。"
  exit 1
fi

# 解壓 XRAY
echo "解壓 XRAY..."
unzip -o /tmp/Xray-linux-64.zip -d /usr/local/bin/
if [ $? -ne 0 ]; then
  echo "解壓 XRAY 失敗。"
  exit 1
fi

# 賦予執行權限
chmod +x /usr/local/bin/xray

# 生成 UUID
echo "生成 UUID..."
UUID=$(cat /proc/sys/kernel/random/uuid)
echo "生成的 UUID：$UUID"

# 配置文件路徑
CONFIG_PATH="/etc/xray/config.json"

# 獲取伺服器的外部 IPv4 地址
EXTERNAL_IPV4=$(ip -4 route get 1.1.1.1 | awk '{print $7}' | head -n1)
if [ -z "$EXTERNAL_IPV4" ]; then
  echo "未檢測到外部 IPv4 地址。請確保伺服器已配置 IPv4 地址。"
  exit 1
fi

# 獲取伺服器的外部 IPv6 地址（如果存在）
EXTERNAL_IPV6=$(ip -6 route get 2001:4860:4860::8888 | awk '{print $7}' | head -n1)
if [ -z "$EXTERNAL_IPV6" ]; then
  echo "未檢測到外部 IPv6 地址，將僅配置 IPv4。"
  IPV6_ENABLED=0
else
  IPV6_ENABLED=1
fi

# 創建 XRAY 配置文件
echo "生成配置文件：$CONFIG_PATH"
cat <<EOF >"$CONFIG_PATH"
{
  "inbounds": [
    {
      "port": 443,
      "listen": "::",  // 支持 IPv4 和 IPv6
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "alterId": 64
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",  // 啟用 TLS 增強安全性
        "tlsSettings": {
          "certificates": [
            {
              "certificateFile": "/etc/xray/fullchain.pem",  // SSL 證書路徑
              "keyFile": "/etc/xray/privkey.pem"            // SSL 私鑰路徑
            }
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF

echo "配置文件已生成：$CONFIG_PATH"

# 安裝 SSL 證書（使用 Let's Encrypt 的 Certbot）
echo "安裝 Certbot 並獲取 SSL 證書..."
apt install -y certbot
if [ $? -ne 0 ]; then
  echo "安裝 Certbot 失敗。"
  exit 1
fi

# 請確保您已經將域名指向伺服器的 IPv4 和 IPv6 地址
DOMAIN="yourdomain.com"  # 請替換為您的域名

# 獲取 SSL 證書
certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos -m your-email@example.com
if [ $? -ne 0 ]; then
  echo "獲取 SSL 證書失敗。請確保域名已正確解析並重試。"
  exit 1
fi

# 設置證書路徑
echo "設置證書路徑..."
sed -i "s|/etc/xray/fullchain.pem|/etc/letsencrypt/live/$DOMAIN/fullchain.pem|g" $CONFIG_PATH
sed -i "s|/etc/xray/privkey.pem|/etc/letsencrypt/live/$DOMAIN/privkey.pem|g" $CONFIG_PATH

# 設置配置文件的權限
echo "設置配置文件權限..."
chown root:root "$CONFIG_PATH"
chmod 644 "$CONFIG_PATH"

# 創建 Systemd 服務文件
echo "創建 Systemd 服務文件..."
cat <<EOF > /etc/systemd/system/xray.service
[Unit]
Description=XRAY Service
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 重新加載 Systemd 配置
echo "重新加載 Systemd 配置..."
systemctl daemon-reload

# 啟動並啟用 XRAY 服務
echo "啟動並啟用 XRAY 服務..."
systemctl start xray
systemctl enable xray

# 檢查 XRAY 服務狀態
echo "檢查 XRAY 服務狀態..."
if systemctl is-active --quiet xray; then
  echo "XRAY 服務已成功啟動並正在運行。"
else
  echo "XRAY 服務啟動失敗，請檢查配置文件或日誌。"
  exit 1
fi

# 設置防火牆規則
echo "設置防火牆規則以允許端口 443 的流量..."
if command -v ufw &>/dev/null; then
  ufw allow 443/tcp
  ufw allow 443/udp
  ufw reload
  echo "已使用 UFW 添加防火牆規則。"
elif command -v firewall-cmd &>/dev/null; then
  firewall-cmd --permanent --add-port=443/tcp
  firewall-cmd --permanent --add-port=443/udp
  firewall-cmd --reload
  echo "已使用 firewalld 添加防火牆規則。"
else
  iptables -I INPUT -p tcp --dport 443 -j ACCEPT
  iptables -I INPUT -p udp --dport 443 -j ACCEPT
  ip6tables -I INPUT -p tcp --dport 443 -j ACCEPT
  ip6tables -I INPUT -p udp --dport 443 -j ACCEPT
  echo "已使用 iptables 添加防火牆規則。"
  # 持久化 iptables 規則
  if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
  elif command -v iptables-save &>/dev/null; then
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
  fi
fi

echo "防火牆規則已設置。"

# 完成提示
echo "XRAY 代理服務器配置完成！"
echo "請使用以下資訊配置您的客戶端："
echo "地址: $DOMAIN"
echo "端口: 443"
echo "協議: VLESS"
echo "UUID: $UUID"
echo "傳輸方式: TCP/TLS"

# 測試代理連接（可選）
echo "正在測試代理連接..."
sleep 5
TEST_IP=$(curl -s --socks5h://$USERNAME:$PASSWORD@$EXTERNAL_IPV4:443 https://api.ipify.org)
if [ -n "$TEST_IP" ]; then
  echo "代理連接成功。代理外網 IP 為：$TEST_IP"
else
  echo "代理連接失敗。請檢查配置或日誌。"
fi

echo "配置完成！"
