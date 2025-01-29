#!/bin/bash

# 一鍵安裝 XRAY 適用於 Debian
echo "==============================="
echo "  XRAY 代理服務器安裝腳本"
echo "  只安裝 XRAY，不創建代理"
echo "==============================="

# 檢查是否以 root 身份運行
if [ "$EUID" -ne 0 ]; then
  echo "請以 root 身份運行此腳本。"
  exit 1
fi

# 設置時區為 Asia/Taipei
echo "設置時區為 Asia/Taipei..."
timedatectl set-timezone Asia/Taipei
if [ $? -eq 0 ]; then
  echo "當前時區：$(timedatectl show -p Timezone --value)"
else
  echo "設置時區失敗，請手動確認系統時區。"
fi

# 禁用 IPv6 支持
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
grep -q "^net.ipv6.conf.all.disable_ipv6=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
grep -q "^net.ipv6.conf.default.disable_ipv6=1" /etc/sysctl.conf || echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf

# 更新套件列表和安裝必要依賴
apt update -y
apt install -y wget unzip

# 下載並安裝 XRAY
XRAY_VERSION="1.8.3"
echo "下載並安裝 XRAY..."
if [ ! -x /usr/local/bin/xray ]; then
  wget https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-linux-64.zip -O /tmp/Xray-linux-64.zip
  unzip -o /tmp/Xray-linux-64.zip -d /usr/local/bin/
  chmod +x /usr/local/bin/xray
  echo "XRAY 安裝完成！"
else
  echo "XRAY 已安裝，跳過下載與安裝。"
fi

echo "XRAY 已成功安裝，你可以手動編寫 /etc/xray/config.json 來配置代理服務。"
