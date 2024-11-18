#!/bin/bash

# 一鍵配置 Dante Server 適用於 Amazon Linux 2023
echo "開始配置 Dante 代理服務器 (Amazon Linux 2023)..."

# 檢查是否以 root 身份運行
if [ "$EUID" -ne 0 ]; then
  echo "請以 root 身份運行此腳本。"
  exit 1
fi

# 更新套件列表
echo "更新套件列表..."
dnf update -y
if [ $? -ne 0 ]; then
  echo "套件列表更新失敗。"
  exit 1
fi

# 安裝必要的依賴包
echo "安裝必要的依賴包..."
dnf install -y gcc make libwrap-devel openssl-devel wget tar
if [ $? -ne 0 ]; then
  echo "安裝依賴包失敗。"
  exit 1
fi

# 定義 Dante 的版本
DANTE_VERSION="1.4.3"

# 下載 Dante 源碼
echo "下載 Dante 源碼..."
cd /usr/local/src || { echo "無法進入 /usr/local/src 目錄。"; exit 1; }
wget https://www.inet.no/dante/files/dante-$DANTE_VERSION.tar.gz
if [ $? -ne 0 ]; then
  echo "下載 Dante 源碼失敗。"
  exit 1
fi

# 解壓源碼
echo "解壓源碼..."
tar -xzf dante-$DANTE_VERSION.tar.gz
if [ $? -ne 0 ]; then
  echo "解壓 Dante 源碼失敗。"
  exit 1
fi

cd dante-$DANTE_VERSION || { echo "無法進入 Dante 源碼目錄。"; exit 1; }

# 編譯並安裝 Dante
echo "編譯並安裝 Dante..."
./configure --prefix=/usr/local --sysconfdir=/etc
if [ $? -ne 0 ]; then
  echo "Dante configure 失敗。請檢查 configure 日誌。"
  exit 1
fi

make
if [ $? -ne 0 ]; then
  echo "Dante make 失敗。請檢查錯誤訊息。"
  exit 1
fi

make install
if [ $? -ne 0 ]; then
  echo "Dante make install 失敗。請檢查錯誤訊息。"
  exit 1
fi

# 確認 Dante 安裝成功
if [ ! -f /usr/local/sbin/sockd ]; then
  echo "Dante 編譯或安裝失敗。請檢查錯誤訊息。"
  exit 1
fi
echo "Dante 已成功編譯並安裝。"

# 配置文件路徑
CONF_PATH="/etc/danted.conf"

# 創建 Dante 配置
echo "生成配置文件：$CONF_PATH"
cat <<EOF >"$CONF_PATH"
logoutput: syslog

internal: 0.0.0.0 port = 3128   # IPv4 監聽端口
internal: :: port = 3128        # IPv6 監聽端口

external: 0.0.0.0               # IPv4 外部地址
external: ::                    # IPv6 外部地址

method: username                # 使用帳號密碼驗證

user.privileged: root
user.notprivileged: proxy
user.libwrap: proxy

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

# 創建代理用戶（如果未存在）
USERNAME="proxyuser"
PASSWORD="X3KVTD6tsFkTtuf5"

if id "$USERNAME" &>/dev/null; then
  echo "用戶 $USERNAME 已存在。"
else
  echo "創建用戶 $USERNAME..."
  useradd -M -s /usr/sbin/nologin "$USERNAME"
  echo "$USERNAME:$PASSWORD" | chpasswd
  echo "用戶 $USERNAME 已創建並設置密碼。"
fi

# 確保 'proxy' 用戶存在，並設置為非特權用戶
PROXY_USER="proxy"
if id "$PROXY_USER" &>/dev/null; then
  echo "用戶 $PROXY_USER 已存在。"
else
  echo "創建用戶 $PROXY_USER 作為非特權用戶..."
  useradd -r -s /usr/sbin/nologin "$PROXY_USER"
  echo "用戶 $PROXY_USER 已創建。"
fi

# 設置配置文件的權限
echo "設置配置文件權限..."
chown root:root "$CONF_PATH"
chmod 644 "$CONF_PATH"

# 創建 systemd 服務文件
echo "創建 systemd 服務文件..."
cat <<EOF > /etc/systemd/system/danted.service
[Unit]
Description=Dante SOCKS Proxy Server
After=network.target

[Service]
Type=forking
ExecStart=/usr/local/sbin/sockd -f /etc/danted.conf
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/sockd.pid

[Install]
WantedBy=multi-user.target
EOF

# 重新加載 systemd 配置
echo "重新加載 systemd 配置..."
systemctl daemon-reload

# 啟動並啟用 Dante 服務
echo "啟動並啟用 Dante 服務..."
systemctl start danted
systemctl enable danted

# 檢查 Dante 服務狀態
echo "檢查 Dante 服務狀態..."
if systemctl is-active --quiet danted; then
  echo "Dante 服務已成功啟動並正在運行。"
else
  echo "Dante 服務啟動失敗，請檢查配置文件或日誌。"
  exit 1
fi

# 設置防火牆規則
echo "設置防火牆規則以允許端口 3128 的流量..."
if command -v firewall-cmd &>/dev/null; then
  firewall-cmd --permanent --add-port=3128/tcp
  firewall-cmd --permanent --add-port=3128/udp
  firewall-cmd --reload
  echo "已使用 firewalld 添加防火牆規則。"
elif command -v iptables &>/dev/null; then
  iptables -I INPUT -p tcp --dport 3128 -j ACCEPT
  iptables -I INPUT -p udp --dport 3128 -j ACCEPT
  ip6tables -I INPUT -p tcp --dport 3128 -j ACCEPT
  ip6tables -I INPUT -p udp --dport 3128 -j ACCEPT
  echo "已使用 iptables 添加防火牆規則。"
  # 持久化 iptables 規則
  if command -v netfilter-persistent &>/dev/null; then
    netfilter-persistent save
  elif command -v iptables-save &>/dev/null; then
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
  fi
else
  echo "未檢測到防火牆管理工具（firewalld 或 iptables）。請手動設置防火牆規則。"
fi

echo "防火牆規則已設置。"

# 完成提示
echo "Dante 代理服務器配置完成！"
echo "請使用以下資訊測試代理服務："
echo "地址: <伺服器IP>:3128"
echo "用戶名: $USERNAME"
echo "密碼: $PASSWORD"

# 測試代理連接（可選）
echo "正在測試代理連接..."
sleep 2
TEST_IP=$(curl -s --socks5-hostname "$USERNAME:$PASSWORD@localhost:3128" https://api.ipify.org)
if [ -n "$TEST_IP" ]; then
  echo "代理連接成功。代理外網 IP 為：$TEST_IP"
else
  echo "代理連接失敗。請檢查配置或日誌。"
fi

echo "配置完成！"
