#!/bin/bash

# 一鍵配置 XRAY HTTP 代理服務器（雙棧支持）適用於 Debian
echo "==============================="
echo "  XRAY HTTP 代理服務器安裝腳本"
echo "  支持 IPv4 和 IPv6 雙棧協議"
echo "==============================="

# 檢查是否以 root 身份運行
if [ "$EUID" -ne 0 ]; then
  echo "請以 root 身份運行此腳本。"
  exit 1
fi

# 定義預設值
DEFAULT_USERNAME="proxyuser"
DEFAULT_PASSWORD="X3KVTD6tsFkTtuf5"
DEFAULT_PORT=1080
XRAY_VERSION="1.8.3"  # 請根據官方最新版本進行更新

# 提示用戶輸入自定義值，若無輸入則使用預設值
read -p "請輸入代理用戶名 [預設: $DEFAULT_USERNAME]: " PROXY_USERNAME
PROXY_USERNAME=${PROXY_USERNAME:-$DEFAULT_USERNAME}

read -s -p "請輸入代理密碼 [預設: $DEFAULT_PASSWORD]: " PROXY_PASSWORD
echo
PROXY_PASSWORD=${PROXY_PASSWORD:-$DEFAULT_PASSWORD}

read -p "請輸入代理端口 [預設: $DEFAULT_PORT]: " PROXY_PORT
PROXY_PORT=${PROXY_PORT:-$DEFAULT_PORT}

echo "--------------------------------"
echo "  代理用戶名: $PROXY_USERNAME"
echo "  代理密碼: $PROXY_PASSWORD"
echo "  代理端口: $PROXY_PORT"
echo "--------------------------------"

# 定義路徑
CONFIG_PATH="/etc/xray/config.json"
SERVICE_PATH="/etc/systemd/system/xray.service"

# 更新套件列表
echo "更新套件列表..."
apt update -y
if [ $? -ne 0 ]; then
  echo "套件列表更新失敗。"
  exit 1
fi

# 安裝必要的依賴包
echo "安裝必要的依賴包..."
apt install -y wget unzip
if [ $? -ne 0 ]; then
  echo "安裝依賴包失敗。"
  exit 1
fi

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

# 創建代理用戶（如果未存在）
if id "$PROXY_USERNAME" &>/dev/null; then
  echo "用戶 $PROXY_USERNAME 已存在。"
else
  echo "創建用戶 $PROXY_USERNAME..."
  useradd -M -s /usr/sbin/nologin "$PROXY_USERNAME"
  echo "$PROXY_USERNAME:$PROXY_PASSWORD" | chpasswd
  echo "用戶 $PROXY_USERNAME 已創建並設置密碼。"
fi

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

# 確保 /etc/xray 目錄存在
echo "確保 /etc/xray 目錄存在..."
mkdir -p /etc/xray
if [ $? -ne 0 ]; then
  echo "無法創建 /etc/xray 目錄。"
  exit 1
fi

# 創建 XRAY 配置文件
echo "生成配置文件：$CONFIG_PATH"
cat <<EOF >"$CONFIG_PATH"
{
  "inbounds": [
    {
      "port": $PROXY_PORT,
      "listen": "::",  // 監聽所有 IPv4 和 IPv6 地址
      "protocol": "http",
      "settings": {
        "accounts": [
          {
            "user": "$PROXY_USERNAME",
            "pass": "$PROXY_PASSWORD"
          }
        ],
        "timeout": 0,
        "allowTransparent": false
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

echo "配置文件已生成：$CONFIG_PATH"

# 設置配置文件的權限
echo "設置配置文件權限..."
chown root:root "$CONFIG_PATH"
chmod 644 "$CONFIG_PATH"

# 創建 Systemd 服務文件
echo "創建 Systemd 服務文件：$SERVICE_PATH"
cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=XRAY HTTP Proxy Service
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

# 提供代理連接資訊
SERVER_IP_V4=$(hostname -I | awk '{print $1}')
SERVER_IP_V6="[$EXTERNAL_IPV6]"

echo "--------------------------------"
echo "XRAY HTTP 代理服務器配置完成！"
echo "請使用以下資訊配置您的客戶端："
echo "--------------------------------"
echo "代理地址 (IPv4): $SERVER_IP_V4:$PROXY_PORT"
if [ $IPV6_ENABLED -eq 1 ]; then
  echo "代理地址 (IPv6): $SERVER_IP_V6:$PROXY_PORT"
fi
echo "用戶名: $PROXY_USERNAME"
echo "密碼: $PROXY_PASSWORD"
echo "--------------------------------"

# 測試代理連接（可選）
echo "正在測試代理連接..."
sleep 5
TEST_IP=$(curl -s --proxy http://$PROXY_USERNAME:$PROXY_PASSWORD@$EXTERNAL_IPV4:$PROXY_PORT https://api.ipify.org)
if [ -n "$TEST_IP" ]; then
  echo "代理連接成功。代理外網 IP 為：$TEST_IP"
else
  echo "代理連接失敗。請檢查配置或日誌。"
fi

echo "配置完成！"
