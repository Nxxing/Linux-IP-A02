#!/bin/bash

# 確保以 root 權限運行
if [ "$EUID" -ne 0 ]; then
  echo "請以 root 權限運行該腳本"
  exit
fi

# 配置參數
SCRIPT_PATH="/usr/local/bin/update_danted_external.sh"
SERVICE_PATH="/etc/systemd/system/update-danted.service"
CONFIG_FILE="/etc/danted.conf"

# 檢查 Danted 是否已安裝
if ! command -v danted &> /dev/null; then
  echo "Danted 未安裝，請先安裝 Danted"
  exit
fi

# 創建更新腳本
echo "創建更新腳本..."
cat > $SCRIPT_PATH <<EOL
#!/bin/bash

# 配置文件路徑
CONFIG_FILE="$CONFIG_FILE"

# 獲取當前的私有 IPv4 地址
PRIVATE_IPV4=\$(ip -4 addr show | grep -oP '(?<=inet\\s)172\\.\\d+\\.\\d+\\.\\d+' | head -n 1)

if [ -z "\$PRIVATE_IPV4" ]; then
  echo "未找到私有 IPv4 地址，請確認網絡設置。"
  exit 1
fi

# 備份原始配置文件
cp \$CONFIG_FILE "\${CONFIG_FILE}.bak_\$(date +%Y%m%d%H%M%S)"

# 更新 external 條目
sed -i -E "s/(external:).*/\\1 \$PRIVATE_IPV4/" \$CONFIG_FILE

# 重啟 Danted 服務
if systemctl restart danted; then
  echo "Danted 配置已更新，external 綁定到私有 IPv4: \$PRIVATE_IPV4"
else
  echo "重啟 Danted 失敗，請檢查配置文件和日誌。"
  exit 1
fi
EOL

# 設置執行權限
chmod +x $SCRIPT_PATH
echo "更新腳本創建完成：$SCRIPT_PATH"

# 創建 systemd 服務
echo "創建 systemd 服務..."
cat > $SERVICE_PATH <<EOL
[Unit]
Description=Update Danted external IP on boot
After=network.target

[Service]
ExecStart=$SCRIPT_PATH
Type=oneshot

[Install]
WantedBy=multi-user.target
EOL

# 啟用服務
echo "啟用開機自動執行..."
systemctl enable update-danted.service

# 立即執行一次以測試
echo "立即測試更新腳本..."
bash $SCRIPT_PATH

echo "設置完成！已啟用開機自動更新 Danted 配置的功能。"
