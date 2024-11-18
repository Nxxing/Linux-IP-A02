#!/bin/bash

# 確保以 root 權限運行
if [ "$EUID" -ne 0 ]; then
  echo "請以 root 權限運行該腳本"
  exit
fi

# 檢查 Danted 是否已安裝
if ! command -v danted &> /dev/null; then
  echo "Danted 未安裝，請先安裝 Danted"
  exit
fi

# 配置文件路徑
CONFIG_FILE="/etc/danted.conf"

# 獲取主要網絡接口
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}')

# 配置文件內容
cat > $CONFIG_FILE <<EOL
logoutput: /var/log/danted.log

internal: 0.0.0.0 port = 3128
internal: :: port = 3128
external: $PRIMARY_INTERFACE

method: username none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
}
client pass {
    from: ::/0 to: ::/0
    log: connect disconnect
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: connect disconnect
}
socks pass {
    from: ::/0 to: ::/0
    log: connect disconnect
}
EOL

# 設置適當的權限
chmod 600 $CONFIG_FILE

# 重啟 Danted 服務
echo "正在重啟 Danted 服務..."
if systemctl restart danted; then
  echo "Danted 配置完成，代理已綁定到端口 3128"
else
  echo "Danted 重啟失敗，請檢查配置文件或日誌 /var/log/danted.log"
  exit
fi

# 測試提示
echo "您可以使用以下命令測試代理服務："
echo "curl --socks5 127.0.0.1:3128 http://ipv4.icanhazip.com"
echo "curl --socks5 127.0.0.1:3128 http://ipv6.icanhazip.com"
