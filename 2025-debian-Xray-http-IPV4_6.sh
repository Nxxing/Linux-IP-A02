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

# 設置時區為 Asia/Taipei 並使用 24 小時制
echo "設置時區為 Asia/Taipei..."
timedatectl set-timezone Asia/Taipei
if [ $? -eq 0 ]; then
  echo "當前時區：$(timedatectl show -p Timezone --value)"
else
  echo "設置時區失敗。請手動確認系統時區。"
fi

# 定義預設值
DEFAULT_USERNAME="proxyuser"
DEFAULT_PASSWORD="X3KVTD6tsFkTtuf5"
DEFAULT_PORT=1080
DEFAULT_PROTOCOL="socks"
XRAY_VERSION="1.8.3"

# 使用命令列參數，如果未提供則使用預設值
MODE=$1
shift
PROXY_PORT=${1:-$DEFAULT_PORT}
PROXY_USERNAME=${2:-$DEFAULT_USERNAME}
PROXY_PASSWORD=${3:-$DEFAULT_PASSWORD}
PROTOCOL=${4:-$DEFAULT_PROTOCOL}

if [ -z "$5" ]; then
  EXPIRATION_DATE=$(date -d "+1 month" "+%Y-%m-%d %H:%M:%S")
else
  EXPIRATION_DATE="$5"
fi

echo "操作模式: $MODE"
echo "端口: $PROXY_PORT, 用戶名: $PROXY_USERNAME, 密碼: $PROXY_PASSWORD, 協議: $PROTOCOL, 到期日: $EXPIRATION_DATE"

# 禁用 IPv6 支持
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
grep -q "^net.ipv6.conf.all.disable_ipv6=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
grep -q "^net.ipv6.conf.default.disable_ipv6=1" /etc/sysctl.conf || echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf

# 檢查端口占用（此部分保持不變）
PORT_IN_USE=$(ss -tuln | grep ":$PROXY_PORT ")
if [ -n "$PORT_IN_USE" ]; then
  echo "端口 $PROXY_PORT 已被佔用，正在終止相關進程..."
  PIDS=$(lsof -i TCP:$PROXY_PORT -t)
  [ -n "$PIDS" ] && kill -9 $PIDS && echo "終止 TCP 進程: $PIDS"
  PIDS_UDP=$(lsof -i UDP:$PROXY_PORT -t)
  [ -n "$PIDS_UDP" ] && kill -9 $PIDS_UDP && echo "終止 UDP 進程: $PIDS_UDP"
else
  echo "端口 $PROXY_PORT 未被佔用。"
fi

# 設置配置文件命名規則（僅使用日期，不含時間秒數）
CURRENT_DATE=$(date +%Y%m%d)
CONFIG_PATH="/etc/xray/config_${PROXY_PORT}_${CURRENT_DATE}.json"
SERVICE_NAME="xray_${PROXY_PORT}"
SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

# 更新套件列表和安裝必要依賴包
apt update -y
apt install -y wget unzip at

# 下載並安裝 XRAY 如果尚未安裝
if [ ! -x /usr/local/bin/xray ]; then
  wget https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-linux-64.zip -O /tmp/Xray-linux-64.zip
  unzip -o /tmp/Xray-linux-64.zip -d /usr/local/bin/
  chmod +x /usr/local/bin/xray
else
  echo "XRAY 已安裝，跳過下載與安裝。"
fi

# 創建用戶如果未存在
if ! id "$PROXY_USERNAME" &>/dev/null; then
  useradd -M -s /usr/sbin/nologin "$PROXY_USERNAME"
  echo "$PROXY_USERNAME:$PROXY_PASSWORD" | chpasswd
  echo "用戶 $PROXY_USERNAME 已創建並設置密碼。"
else
  echo "用戶 $PROXY_USERNAME 已存在。"
fi

mkdir -p /etc/xray

# 根據協議生成配置文件
echo "生成配置文件：$CONFIG_PATH"
case "$PROTOCOL" in
  socks)
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
    ;;
  ss)
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
    ;;
  vless)
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
    ;;
  http)
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
    ;;
  *)
    echo "不支持的協議類型：$PROTOCOL"
    exit 1
    ;;
esac

echo "配置文件已生成：$CONFIG_PATH"

chown root:root "$CONFIG_PATH"
chmod 644 "$CONFIG_PATH"

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

echo "確保 atd 服務正在運行..."
systemctl enable --now atd

AT_TIME=$(date -d "$EXPIRATION_DATE" +"%Y%m%d%H%M" 2>/dev/null)
if [ $? -ne 0 ]; then
  echo "到期日期格式錯誤，請使用 'YYYY-MM-DD HH:MM:SS' 格式。"
  exit 1
fi

# 若模式為續約相關，取消現有 at 任務
if [[ "$MODE" == "--renew" || "$MODE" == "--renew-update" ]]; then
  echo "檢測到續約操作，查找並取消現有的 at 任務..."
  atq | awk '{print $1}' | while read job; do
    if at -c $job 2>/dev/null | grep -q "systemctl stop ${SERVICE_NAME}.service"; then
      atrm $job
      echo "取消現有的 at 任務: $job"
    fi
  done
fi

STOP_CMD="systemctl stop ${SERVICE_NAME}.service && systemctl disable ${SERVICE_NAME}.service && rm /etc/systemd/system/${SERVICE_NAME}.service && rm $CONFIG_PATH && systemctl daemon-reload"
echo "$STOP_CMD" | at -t "$AT_TIME"
if [ $? -eq 0 ]; then
  echo "服務將在 $EXPIRATION_DATE 自動停止並清理。"
else
  echo "排程自動停止服務失敗。請檢查 atd 服務是否運行正常。"
  exit 1
fi

echo "配置完成！"
