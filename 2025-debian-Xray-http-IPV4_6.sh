#!/bin/bash

# 一鍵配置 XRAY 代理服務器適用於 Debian
echo "==============================="
echo "  XRAY 代理服務器安裝腳本"
echo "  支持多協議（僅 IPv4，UDP），多服務共存"
echo "==============================="

# 檢查是否以 root 身份運行
if [ "$EUID" -ne 0 ]; then
  echo "請以 root 身份運行此腳本。"
  exit 1
fi

# 設置系統時區為台北
echo "設置時區為 Asia/Taipei..."
timedatectl set-timezone Asia/Taipei
if [ $? -eq 0 ]; then
  echo "時區已設定為 $(timedatectl show -p Timezone --value)"
else
  echo "設置時區失敗。請手動確認系統時區。"
fi

# 定義預設值
DEFAULT_USERNAME="proxyuser"
DEFAULT_PASSWORD="X3KVTD6tsFkTtuf5"
DEFAULT_PORT=1080
DEFAULT_PROTOCOL="socks"
XRAY_VERSION="1.8.3"  # 根據需要更新至最新版本

# 使用命令列參數，如果未提供則使用預設值
PROXY_PORT=${1:-$DEFAULT_PORT}
PROXY_USERNAME=${2:-$DEFAULT_USERNAME}
PROXY_PASSWORD=${3:-$DEFAULT_PASSWORD}
PROTOCOL=${4:-$DEFAULT_PROTOCOL}

# 設定到期日參數
if [ -z "$5" ]; then
  EXPIRATION_DATE=$(date -d "+1 month" "+%Y-%m-%d %H:%M:%S")
else
  EXPIRATION_DATE="$5"
fi

echo "--------------------------------"
echo "  協議類型: $PROTOCOL"
echo "  代理用戶名: $PROXY_USERNAME"
echo "  代理密碼: $PROXY_PASSWORD"
echo "  代理端口: $PROXY_PORT"
echo "  服務到期日: $EXPIRATION_DATE"
echo "--------------------------------"

# 禁用 IPv6 支持
echo "禁用系統 IPv6 支持..."
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
grep -q "^net.ipv6.conf.all.disable_ipv6=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
grep -q "^net.ipv6.conf.default.disable_ipv6=1" /etc/sysctl.conf || echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf

# 檢查端口是否被佔用，若被佔用則終止相關進程
echo "檢查端口 $PROXY_PORT 是否被佔用..."
PORT_IN_USE=$(ss -tuln | grep ":$PROXY_PORT ")
if [ -n "$PORT_IN_USE" ]; then
  echo "端口 $PROXY_PORT 已被佔用，正在終止相關進程..."
  PIDS=$(lsof -i TCP:$PROXY_PORT -t)
  if [ -n "$PIDS" ]; then
    echo "終止進程: $PIDS"
    kill -9 $PIDS
    echo "進程已終止。"
  fi
  PIDS_UDP=$(lsof -i UDP:$PROXY_PORT -t)
  if [ -n "$PIDS_UDP" ]; then
    echo "終止 UDP 進程: $PIDS_UDP"
    kill -9 $PIDS_UDP
    echo "UDP 進程已終止。"
  fi
else
  echo "端口 $PROXY_PORT 未被佔用。"
fi

# 定義時間戳和配置路徑
TIMESTAMP=$(date +%Y%m%d%H%M%S)
CONFIG_PATH="/etc/xray/config_${PROXY_PORT}_${TIMESTAMP}.json"
SERVICE_NAME="xray_${PROXY_PORT}"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# 更新套件列表和安裝必要依賴包
echo "更新套件列表..."
apt update -y || { echo "套件列表更新失敗。"; exit 1; }
echo "安裝必要的依賴包..."
apt install -y wget unzip at || { echo "安裝依賴包失敗。"; exit 1; }

# 下載並安裝 XRAY
echo "下載 XRAY..."
wget https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-linux-64.zip -O /tmp/Xray-linux-64.zip || { echo "下載 XRAY 失敗。"; exit 1; }
echo "解壓 XRAY..."
unzip -o /tmp/Xray-linux-64.zip -d /usr/local/bin/ || { echo "解壓 XRAY 失敗。"; exit 1; }
chmod +x /usr/local/bin/xray

# 創建代理用戶（如果未存在）
if id "$PROXY_USERNAME" &>/dev/null; then
  echo "用戶 $PROXY_USERNAME 已存在。"
else
  useradd -M -s /usr/sbin/nologin "$PROXY_USERNAME"
  echo "$PROXY_USERNAME:$PROXY_PASSWORD" | chpasswd
  echo "用戶 $PROXY_USERNAME 已創建並設置密碼。"
fi

# 確保 /etc/xray 目錄存在
mkdir -p /etc/xray || { echo "無法創建 /etc/xray 目錄。"; exit 1; }

# 根據協議生成配置文件
echo "生成配置文件：$CONFIG_PATH"
if [ "$PROTOCOL" = "socks" ]; then
  cat <<EOF >"$CONFIG_PATH"
{
  "inbounds": [
    {
      "port": $PROXY_PORT,
      "listen": "0.0.0.0",
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "$PROXY_USERNAME",
            "pass": "$PROXY_PASSWORD"
          }
        ],
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": []
  }
}
EOF

elif [ "$PROTOCOL" = "ss" ]; then
  cat <<EOF >"$CONFIG_PATH"
{
  "inbounds": [
    {
      "port": $PROXY_PORT,
      "listen": "0.0.0.0",
      "protocol": "shadowsocks",
      "settings": {
        "method": "aes-256-gcm",
        "password": "$PROXY_PASSWORD",
        "udp": true
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": []
  }
}
EOF

elif [ "$PROTOCOL" = "vless" ]; then
  cat <<EOF >"$CONFIG_PATH"
{
  "inbounds": [
    {
      "port": $PROXY_PORT,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "d290f1ee-6c54-4b01-90e6-d701748f0851",
            "flow": ""
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp"
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": []
  }
}
EOF
  echo "使用預設 VLESS UUID: d290f1ee-6c54-4b01-90e6-d701748f0851"

elif [ "$PROTOCOL" = "http" ]; then
  cat <<EOF >"$CONFIG_PATH"
{
  "inbounds": [
    {
      "port": $PROXY_PORT,
      "listen": "0.0.0.0",
      "protocol": "http",
      "settings": {
        "accounts": [
          {
            "user": "$PROXY_USERNAME",
            "pass": "$PROXY_PASSWORD"
          }
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": []
  }
}
EOF

else
  echo "不支持的協議類型：$PROTOCOL"
  exit 1
fi

echo "配置文件已生成：$CONFIG_PATH"

# 設置配置文件的權限
chown root:root "$CONFIG_PATH"
chmod 644 "$CONFIG_PATH"

# 創建 Systemd 服務文件
echo "創建 Systemd 服務文件：$SERVICE_PATH"
cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=XRAY $PROTOCOL Proxy Service on port $PROXY_PORT
After=network.target

[Service]
User=root
ExecStart=/usr/local/bin/xray run -config $CONFIG_PATH
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

echo "重新加載 Systemd 配置..."
systemctl daemon-reload

echo "停止現有的 XRAY 服務（如果存在）..."
systemctl stop ${SERVICE_NAME}.service 2>/dev/null

echo "啟動並啟用 XRAY 服務..."
systemctl start ${SERVICE_NAME}.service
systemctl enable ${SERVICE_NAME}.service

echo "檢查 XRAY 服務狀態..."
if systemctl is-active --quiet ${SERVICE_NAME}.service; then
  echo "XRAY 服務已成功啟動並正在運行。"
else
  echo "XRAY 服務啟動失敗，請檢查配置文件或日誌。"
  exit 1
fi

# 安排在到期時停止並清理服務
apt install -y at || { echo "安裝 at 失敗。"; exit 1; }
STOP_CMD="systemctl stop ${SERVICE_NAME}.service && systemctl disable ${SERVICE_NAME}.service && rm /etc/systemd/system/${SERVICE_NAME}.service && rm $CONFIG_PATH && systemctl daemon-reload"
echo "$STOP_CMD" | at "$EXPIRATION_DATE"
echo "服務將在 $EXPIRATION_DATE 自動停止並清理。"

echo "--------------------------------"
echo "XRAY $PROTOCOL 代理服務器配置完成！"
echo "請使用以下資訊配置您的客戶端："
echo "--------------------------------"
echo "代理地址: $(hostname -I | awk '{print $1}'):$PROXY_PORT"
if [ "$PROTOCOL" = "socks" ] || [ "$PROTOCOL" = "http" ]; then
  echo "用戶名: $PROXY_USERNAME"
  echo "密碼: $PROXY_PASSWORD"
fi
if [ "$PROTOCOL" = "ss" ]; then
  echo "密碼: $PROXY_PASSWORD"
  echo "加密方式: aes-256-gcm"
fi
if [ "$PROTOCOL" = "vless" ]; then
  echo "VLESS UUID: d290f1ee-6c54-4b01-90e6-d701748f0851"
  echo "協議: VLESS+TCP"
fi
echo "服務到期日: $EXPIRATION_DATE"
echo "--------------------------------"

echo "正在測試代理連接..."
sleep 5
if [ "$PROTOCOL" = "socks" ]; then
  TEST_IP=$(curl -s --socks5 $PROXY_USERNAME:$PROXY_PASSWORD@$(hostname -I | awk '{print $1}'):$PROXY_PORT https://api.ipify.org)
elif [ "$PROTOCOL" = "http" ]; then
  TEST_IP=$(curl -s --proxy http://$PROXY_USERNAME:$PROXY_PASSWORD@$(hostname -I | awk '{print $1}'):$PROXY_PORT https://api.ipify.org)
else
  TEST_IP="N/A (請使用支持該協議的客戶端進行測試)"
fi

if [ "$TEST_IP" != "N/A" ] && [ -n "$TEST_IP" ]; then
  echo "代理連接成功。代理外網 IP 為：$TEST_IP"
else
  echo "代理連接測試需使用支持該協議的客戶端進行確認。"
fi

echo "配置完成！"
