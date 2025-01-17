#!/bin/bash

# 檢查是否以 root 身份運行
if [ "$EUID" -ne 0 ]; then
  echo "請以 root 身份運行此腳本。"
  exit 1
fi

# 設置時區為 Asia/Taipei 並使用 24 小時制
timedatectl set-timezone Asia/Taipei

# 禁用 IPv6 支持
sysctl -w net.ipv6.conf.all.disable_ipv6=1
sysctl -w net.ipv6.conf.default.disable_ipv6=1
grep -q "^net.ipv6.conf.all.disable_ipv6=1" /etc/sysctl.conf || echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
grep -q "^net.ipv6.conf.default.disable_ipv6=1" /etc/sysctl.conf || echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf

# 定義預設值
DEFAULT_USERNAME="proxyuser"
DEFAULT_PASSWORD="X3KVTD6tsFkTtuf5"
DEFAULT_PORT=1080
DEFAULT_PROTOCOL="socks"
XRAY_VERSION="1.8.3"

# 獲取模式參數並移除
MODE=$1
shift

# 根據模式讀取參數
PROXY_PORT=${1:-$DEFAULT_PORT}
PROXY_USERNAME=${2:-$DEFAULT_USERNAME}
PROXY_PASSWORD=${3:-$DEFAULT_PASSWORD}
PROTOCOL=${4:-$DEFAULT_PROTOCOL}

# 設定到期日參數（僅對新建、續約模式有用）
if [ -z "$5" ]; then
  EXPIRATION_DATE=$(date -d "+1 month" "+%Y-%m-%d %H:%M:%S")
else
  EXPIRATION_DATE="$5"
fi

echo "操作模式: $MODE"
echo "端口: $PROXY_PORT, 用戶名: $PROXY_USERNAME, 密碼: $PROXY_PASSWORD, 協議: $PROTOCOL, 到期日: $EXPIRATION_DATE"

# 根據不同模式執行對應操作
case "$MODE" in
  --new|--renew-update)
    # 新建或續約+修改：使用完整部署流程
    # （--renew-update 模式將在續約時同時更新憑證）

    # 定義時間戳、配置路徑和服務名稱
    TIMESTAMP=$(date +%Y%m%d%H%M%S)
    CONFIG_PATH="/etc/xray/config_${PROXY_PORT}_${TIMESTAMP}.json"
    SERVICE_NAME="xray_${PROXY_PORT}"
    SERVICE_PATH="/etc/systemd/system/${SERVICE_NAME}.service"

    # 檢查並安裝依賴
    apt update -y
    apt install -y wget unzip at

    # 檢查端口占用 (同前段代碼)...

    # 更新或安裝 XRAY (略，同前段)...
    if [ ! -x /usr/local/bin/xray ]; then
      wget https://github.com/XTLS/Xray-core/releases/download/v$XRAY_VERSION/Xray-linux-64.zip -O /tmp/Xray-linux-64.zip
      unzip -o /tmp/Xray-linux-64.zip -d /usr/local/bin/
      chmod +x /usr/local/bin/xray
    fi

    # 創建用戶 (同前段)...

    # 生成配置文件 (同之前的 case "$PROTOCOL")...
    # [將完整協議配置部分放置在此，以選擇 socks/ss/vless/http 配置]

    # 設置權限、創建 Systemd 服務 (同前段)...

    # 啟動並啟用服務
    systemctl daemon-reload
    systemctl stop ${SERVICE_NAME}.service 2>/dev/null
    systemctl start ${SERVICE_NAME}.service
    systemctl enable ${SERVICE_NAME}.service

    # 安排到期自動停止 (同前段)...
    systemctl enable --now atd
    AT_TIME=$(date -d "$EXPIRATION_DATE" +"%Y%m%d%H%M" 2>/dev/null)
    STOP_CMD="systemctl stop ${SERVICE_NAME}.service && systemctl disable ${SERVICE_NAME}.service && rm /etc/systemd/system/${SERVICE_NAME}.service && rm $CONFIG_PATH && systemctl daemon-reload"
    echo "$STOP_CMD" | at -t "$AT_TIME"
    echo "服務將在 $EXPIRATION_DATE 自動停止並清理。"
    ;;
  
  --update-credentials)
    # 只修改憑證：更新指定端口的配置文件中的用戶名和密碼
    # 假設服務已存在且配置文件位於 /etc/xray/config_${PROXY_PORT}_*.json
    CONFIG_FILE=$(ls /etc/xray/config_${PROXY_PORT}_*.json 2>/dev/null | head -n1)
    if [ -z "$CONFIG_FILE" ]; then
      echo "未找到端口 $PROXY_PORT 的配置文件。"
      exit 1
    fi
    echo "更新配置文件 $CONFIG_FILE 中的憑證..."
    # 根據不同協議更新帳密，這裡僅處理 socks, ss, http 協議
    if [[ "$PROTOCOL" == "socks" || "$PROTOCOL" == "http" ]]; then
      sed -i "s/\"user\": \".*\",/\"user\": \"$PROXY_USERNAME\",/g; s/\"pass\": \".*\"/\"pass\": \"$PROXY_PASSWORD\"/g" "$CONFIG_FILE"
    elif [ "$PROTOCOL" = "ss" ]; then
      sed -i "s/\"password\": \".*\"/\"password\": \"$PROXY_PASSWORD\"/g" "$CONFIG_FILE"
    else
      echo "更新憑證的操作不支持協議類型：$PROTOCOL"
    fi
    echo "重新啟動服務以應用新憑證..."
    systemctl restart xray_${PROXY_PORT}.service
    ;;

  --renew)
    # 只續約：取消現有 at 任務並安排新的停止時間
    echo "續約操作 - 延長到期日..."
    # 找到現有服務名
    SERVICE_NAME="xray_${PROXY_PORT}"
    CONFIG_FILE=$(ls /etc/xray/config_${PROXY_PORT}_*.json 2>/dev/null | head -n1)
    if [ -z "$CONFIG_FILE" ]; then
      echo "未找到端口 $PROXY_PORT 的配置文件，無法續約。"
      exit 1
    fi
    # 查找並取消現有的 at 任務
    atq | awk '{print $1}' | while read job; do
      if at -c $job 2>/dev/null | grep -q "systemctl stop ${SERVICE_NAME}.service"; then
        atrm $job
        echo "取消現有的 at 任務: $job"
      fi
    done
    # 安排新的停止任務
    systemctl enable --now atd
    AT_TIME=$(date -d "$EXPIRATION_DATE" +"%Y%m%d%H%M" 2>/dev/null)
    STOP_CMD="systemctl stop ${SERVICE_NAME}.service && systemctl disable ${SERVICE_NAME}.service && rm /etc/systemd/system/${SERVICE_NAME}.service && rm $CONFIG_FILE && systemctl daemon-reload"
    echo "$STOP_CMD" | at -t "$AT_TIME"
    echo "服務將在 $EXPIRATION_DATE 自動停止並清理。"
    ;;

  --renew-update)
    # 續約+修改密碼：結合 --update-credentials 和 --renew 操作
    echo "進行續約和更新憑證操作..."
    # 先更新憑證
    "$0" --update-credentials "$PROXY_PORT" "$PROXY_USERNAME" "$PROXY_PASSWORD" "$PROTOCOL" "$EXPIRATION_DATE"
    # 然後續約
    "$0" --renew "$PROXY_PORT" "$PROXY_USERNAME" "$PROXY_PASSWORD" "$PROTOCOL" "$EXPIRATION_DATE"
    ;;

  *)
    echo "不支持的模式：$MODE"
    echo "支持的模式：--new, --update-credentials, --renew, --renew-update"
    exit 1
    ;;
esac

echo "操作完成！"
