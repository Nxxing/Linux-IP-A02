#!/bin/bash

# 一鍵配置 XRAY SOCKS5 代理服務器（僅 IPv4，支持帳密驗證和 UDP）適用於 Debian
echo "==============================="
echo "  XRAY SOCKS5 代理服務器安裝腳本"
echo "  僅支持 IPv4，支持帳密驗證和 UDP"
echo "==============================="

# 檢查是否以 root 身份運行
if [ "$EUID" -ne 0 ]; then
  echo "請以 root 身份運行此腳本。"
  exit 1
fi

# 禁用系統 IPv6 支持
echo "禁用系統 IPv6 支持..."
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
# 將設置寫入 /etc/sysctl.conf 以永久生效
if ! grep -q "net.ipv6.conf.all.disable_ipv6=1" /etc/sysctl.conf; then
  echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
fi
if ! grep -q "net.ipv6.conf.default.disable_ipv6=1" /etc/sysctl.conf; then
  echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
fi

# 定義預設值
DEFAULT_USERNAME="xd"
DEFAULT_PASSWORD="xdxd"
DEFAULT_PORT=61111
XRAY_VERSION="1.8.3"  # 根據需要更新至最新版本

# 使用命令列參數，如果未提供則使用預設值
PROXY_PORT=${1:-$DEFAULT_PORT}
PROXY_USERNAME=${2:-$DEFAULT_USERNAME}
PROXY_PASSWORD=${3:-$DEFAULT_PASSWORD}

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
apt update -y || { echo "套件列表更新失敗。"; exit 1; }

# 安裝必要的依賴包
echo "安裝必要的依賴包..."
apt install -y wget unzip || { echo "安裝依賴包失敗。"; exit 1; }

# 下載 XRAY
echo "下載 XRAY..."
wget https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-linux-64.zip -O /tmp/Xray-linux-64.zip \
  || { echo "下載 XRAY 失敗。"; exit 1; }

# 解壓 XRAY
echo "解壓 XRAY..."
unzip -o /tmp/Xray-linux-64.zip -d /usr/local/bin/ \
  || { echo "解壓 XRAY 失敗。"; exit 1; }

chmod +x /usr/local/bin/xray

# 確保 /etc/xray 目錄存在
echo "確保 /etc/xray 目錄存在..."
mkdir -p /etc/xray || { echo "無法創建 /etc/xray 目錄。"; exit 1; }

# 創建 XRAY 配置文件
echo "生成配置文件：$CONFIG_PATH"
cat <<EOF >"$CONFIG_PATH"
{
  "inbounds": [
    {
      "port": $PROXY_PORT,
      "listen": "0.0.0.0",  // 僅 IPv4
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

echo "配置文件已生成：$CONFIG_PATH"

# 設置配置文件的權限
echo "設置配置文件權限..."
chown root:root "$CONFIG_PATH"
chmod 644 "$CONFIG_PATH"

# 創建 Systemd 服務文件
echo "創建 Systemd 服務文件：$SERVICE_PATH"
cat <<EOF > "$SERVICE_PATH"
[Unit]
Description=XRAY SOCKS5 Proxy Service
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

# 停止現有的 XRAY 服務（如果存在）
echo "停止現有的 XRAY 服務（如果存在）..."
systemctl stop xray.service 2>/dev/null

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
SERVER_IP=$(hostname -I | awk '{print $1}')

echo "--------------------------------"
echo "XRAY SOCKS5 代理服務器配置完成！"
echo "請使用以下資訊配置您的客戶端："
echo "--------------------------------"
echo "代理地址: $SERVER_IP:$PROXY_PORT"
echo "用戶名: $PROXY_USERNAME"
echo "密碼: $PROXY_PASSWORD"
echo "加密方式: (不適用於 SOCKS5，僅驗證身份)"
echo "--------------------------------"

# 測試代理連接（可選）
echo "正在測試代理連接..."
sleep 5
TEST_IP=$(curl -s --socks5 $SERVER_IP:$PROXY_PORT https://api.ipify.org)
if [ -n "$TEST_IP" ]; then
  echo "代理連接成功。代理外網 IP 為：$TEST_IP"
else
  echo "代理連接失敗。請檢查配置或日誌。"
fi

echo "配置完成！"
