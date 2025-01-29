#!/bin/bash

# 檢查是否以 root 身份運行
if [ "$EUID" -ne 0 ]; then
  echo "請以 root 身份運行此腳本。"
  exit 1
fi

# 確保 Xray 已安裝
if [ ! -x /usr/local/bin/xray ]; then
  echo "XRAY 未安裝，請先執行 install_xray.sh"
  exit 1
fi

# 設定變數
DEFAULT_USERNAME="proxyuser"
DEFAULT_PASSWORD="X3KVTD6tsFkTtuf5"
DEFAULT_PORT=1080
DEFAULT_PROTOCOL="socks"

PROXY_PORT=${1:-$DEFAULT_PORT}
PROXY_USERNAME=${2:-$DEFAULT_USERNAME}
PROXY_PASSWORD=${3:-$DEFAULT_PASSWORD}
PROTOCOL=${4:-$DEFAULT_PROTOCOL}

echo "創建代理服務: $PROTOCOL"
echo "端口: $PROXY_PORT, 用戶名: $PROXY_USERNAME, 密碼: $PROXY_PASSWORD"

# 檢查端口占用
PORT_IN_USE=$(ss -tuln | grep ":$PROXY_PORT ")
if [ -n "$PORT_IN_USE" ]; then
  echo "端口 $PROXY_PORT 已被佔用，終止相關進程..."
  PIDS=$(lsof -i TCP:$PROXY_PORT -t)
  [ -n "$PIDS" ] && kill -9 $PIDS && echo "終止 TCP 進程: $PIDS"
  PIDS_UDP=$(lsof -i UDP:$PROXY_PORT -t)
  [ -n "$PIDS_UDP" ] && kill -9 $PIDS_UDP && echo "終止 UDP 進程: $PIDS_UDP"
else
  echo "端口 $PROXY_PORT 未被佔用。"
fi

# 設置 Xray 配置文件
CONFIG_PATH="/etc/xray/config_${PROXY_PORT}.json"
SERVICE_NAME="xray_${PROXY_PORT}"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

echo "生成配置文件：$CONFIG_PATH"
mkdir -p /etc/xray

cat <<EOF >"$CONFIG_PATH"
{
  "inbounds": [
    {
      "port": $PROXY_PORT,
      "listen": "0.0.0.0",
      "protocol": "$PROTOCOL",
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
  ]
}
EOF

chown root:root "$CONFIG_PATH"
chmod 644 "$CONFIG_PATH"

# 創建 systemd 服務文件
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

# 重新加載 systemd 並啟動代理服務
echo "重新加載 Systemd 配置..."
systemctl daemon-reload
systemctl stop ${SERVICE_NAME}.service 2>/dev/null
systemctl start ${SERVICE_NAME}.service
systemctl enable ${SERVICE_NAME}.service

echo "XRAY 代理 $PROTOCOL 已啟動，端口：$PROXY_PORT"
