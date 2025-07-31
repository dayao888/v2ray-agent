#!/usr/bin/env bash
set -e

# --- 辅助函数和变量定义 ---
# 颜色定义
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(red "$1")" "$2"; }

# 工作目录定义
WORKDIR="$HOME/sing-box-no-root"
BIN_DIR="$WORKDIR/bin"
CONFIG_DIR="$WORKDIR/config"
LOG_DIR="$WORKDIR/logs"

echo -e "${green}🧹 清理旧目录...${re}"
rm -rf "$WORKDIR"

echo -e "${green}📁 创建工作目录...${re}"
mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR"

# --- 架构检测 (已修正) ---
arch=$(uname -m)
if [[ "$arch" == "x86_64" || "$arch" == "amd64" ]]; then # 修正：添加了对 "amd64" 的支持
    platform="amd64"
elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
    platform="arm64"
else
    echo -e "${red}❌ 不支持的架构: $arch${re}"
    exit 1
fi

# --- 下载 Sing-box ---
# 使用 Sing-box 官方最新版本
version="1.11.9" # 您可以根据需要更改为最新版本
echo -e "${green}📦 下载 Sing-box 版本: $version for Linux $platform...${re}"
url="https://github.com/SagerNet/sing-box/releases/download/v$version/sing-box-$version-linux-$platform.tar.gz"
DOWNLOADED_FILE="$WORKDIR/sing-box.tar.gz"

# 使用 curl 下载，带进度条
if command -v curl >/dev/null 2>&1; then
    curl -L -o "$DOWNLOADED_FILE" "$url"
elif command -v wget >/dev/null 2>&1; then
    wget -O "$DOWNLOADED_FILE" "$url"
else
    echo -e "${red}❌ 无法下载 Sing-box，请确保已安装 curl 或 wget。${re}"
    exit 1
fi

if [ ! -f "$DOWNLOADED_FILE" ]; then
    echo -e "${red}❌ Sing-box 下载失败，文件不存在: $DOWNLOADED_FILE${re}"
    exit 1
fi

echo -e "${green}解压 Sing-box...${re}"
tar -zxf "$DOWNLOADED_FILE" -C "$WORKDIR" --strip-components=1 "sing-box-$version-linux-$platform/sing-box"
mv "$WORKDIR/sing-box" "$BIN_DIR/sing-box"
chmod +x "$BIN_DIR/sing-box"
rm -f "$DOWNLOADED_FILE" # 删除压缩包
rm -rf "$WORKDIR/sing-box-$version-linux-$platform" # 清理解压目录残留

# --- 生成 UUID 和 Reality 密钥 ---
echo -e "${green}🔑 生成 UUID 和 Reality 密钥...${re}"
if command -v uuidgen >/dev/null 2>&1; then
    UUID=$(uuidgen)
else
    # 兼容性处理，使用 openssl 生成类似 UUID 的字符串
    UUID=$(openssl rand -hex 16 | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/')
fi
echo "生成的 UUID: $UUID"

# 使用正确的命令生成 Reality 密钥对
KEYS=$("$BIN_DIR/sing-box" generate reality-keypair)
PRIVATE_KEY=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep PublicKey | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 8)

echo "生成的 PrivateKey: $PRIVATE_KEY"
echo "生成的 PublicKey: $PUBLIC_KEY"
echo "生成的 ShortId: $SHORT_ID"

# --- 定义配置参数 ---
# 建议这里让用户输入，而不是硬编码，或提供默认值并允许修改
DOMAIN="www.5215211.xyz" # 您的域名
PORT=22724 # VLESS Reality 监听端口
HYSTERIA2_PORT=30002 # Hysteria2 监听端口
HYSTERIA2_PASSWORD="mypass123" # Hysteria2 密码，请务必修改为强密码

echo -e "${green}📝 生成 Sing-box VLESS Reality 配置文件...${re}"
cat > "$CONFIG_DIR/vless.json" <<EOF
{
  "log": { "level": "info" },
  "inbounds": [{
    "type": "vless",
    "listen": "0.0.0.0",
    "listen_port": $PORT,
    "users": [{ "uuid": "$UUID", "flow": "xtls-rprx-vision" }],
    "tls": {
      "enabled": true,
      "server_name": "$DOMAIN",
      "reality": {
        "enabled": true,
        "handshake": { "server": "$DOMAIN", "server_port": 443 },
        "private_key": "$PRIVATE_KEY",
        "short_id": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [{ "type": "direct" }]
}
EOF

echo -e "${green}📝 生成 Sing-box Hysteria2 配置文件...${re}"
# 生成自签名 TLS 证书
echo -e "${green}🔐 生成自签名 TLS 证书...${re}"
openssl req -x509 -newkey rsa:2048 -keyout "$CONFIG_DIR/self.key" -out "$CONFIG_DIR/self.crt" -days 365 -nodes -subj "/CN=$DOMAIN" # CN改为您的域名

cat > "$CONFIG_DIR/hysteria2.json" <<EOF
{
  "log": { "level": "info" },
  "inbounds": [{
    "type": "hysteria2",
    "listen": "0.0.0.0",
    "listen_port": $HYSTERIA2_PORT,
    "users": [{ "password": "$HYSTERIA2_PASSWORD" }],
    "tls": {
      "enabled": true,
      "cert": "$CONFIG_DIR/self.crt",
      "key": "$CONFIG_DIR/self.key",
      "alpn": ["h2", "h3"] # 建议添加 ALPN
    }
  }],
  "outbounds": [{ "type": "direct" }]
}
EOF

# --- 生成管理菜单脚本 ---
echo -e "${green}⚙️ 生成管理面板脚本...${re}"
cat > "$WORKDIR/menu.sh" << EOF
#!/usr/bin/env bash
WORKDIR="$HOME/sing-box-no-root"
BIN="$WORKDIR/bin/sing-box"
LOG1="$WORKDIR/logs/vless.log"
LOG2="$WORKDIR/logs/hysteria2.log"
PID_DIR="$WORKDIR/run" # 新增PID文件目录
mkdir -p "$PID_DIR" # 确保PID目录存在
pidfile1="$PID_DIR/vless.pid"
pidfile2="$PID_DIR/hysteria2.pid"

# 颜色定义（在菜单脚本内部也需要）
re="\033[0m"
green="\e[1;32m"
red="\033[1;91m"
yellow="\e[1;33m"

# 检查服务运行状态
check_process() {
    local pidfile=$1
    local service_name=$2
    if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
        echo -e "${green}[$service_name] 正在运行 (PID: $(cat "$pidfile"))${re}"
        return 0
    else
        echo -e "${red}[$service_name] 未运行${re}"
        return 1
    fi
}

start_vless(){
    if check_process "$pidfile1" "VLESS"; then
        echo -e "${yellow}VLESS 已经在运行，无需重复启动。${re}"
        return
    fi
    echo -e "${green}🚀 启动 VLESS Reality...${re}"
    nohup "$BIN" run -c "$WORKDIR/config/vless.json" > "$LOG1" 2>&1 &
    echo $! > "$pidfile1"
    sleep 1 # 等待服务启动
    if check_process "$pidfile1" "VLESS"; then
        echo -e "${green}✅ VLESS 启动成功，端口: $PORT，PID: $(cat $pidfile1)${re}"
    else
        echo -e "${red}❌ VLESS 启动失败，请检查日志: $LOG1${re}"
    fi
}
start_hysteria(){
    if check_process "$pidfile2" "Hysteria2"; then
        echo -e "${yellow}Hysteria2 已经在运行，无需重复启动。${re}"
        return
    fi
    echo -e "${green}🚀 启动 Hysteria2 TLS...${re}"
    nohup "$BIN" run -c "$WORKDIR/config/hysteria2.json" > "$LOG2" 2>&1 &
    echo $! > "$pidfile2"
    sleep 1 # 等待服务启动
    if check_process "$pidfile2" "Hysteria2"; then
        echo -e "${green}✅ Hysteria2 启动成功，端口: $HYSTERIA2_PORT，PID: $(cat $pidfile2)${re}"
    else
        echo -e "${red}❌ Hysteria2 启动失败，请检查日志: $LOG2${re}"
    fi
}
stop_all(){
    echo -e "${yellow}🛑 停止全部服务...${re}"
    local stopped_count=0
    if check_process "$pidfile1" "VLESS"; then
        kill "$(cat "$pidfile1")" 2>/dev/null && rm -f "$pidfile1" && stopped_count=$((stopped_count+1))
        echo -e "${green}VLESS 服务已停止。${re}"
    fi
    if check_process "$pidfile2" "Hysteria2"; then
        kill "$(cat "$pidfile2")" 2>/dev/null && rm -f "$pidfile2" && stopped_count=$((stopped_count+1))
        echo -e "${green}Hysteria2 服务已停止。${re}"
    fi
    if [ "$stopped_count" -eq 0 ]; then
        echo -e "${yellow}没有正在运行的服务需要停止。${re}"
    else
        echo -e "${green}所有已知的 Sing-box 服务已停止。${re}"
    fi
}
show_status(){
    echo -e "\n=== 服务运行状态 ==="
    check_process "$pidfile1" "VLESS"
    check_process "$pidfile2" "Hysteria2"
    echo "======================"
}
show_menu(){
    clear;
    echo -e "${green}=== Sing-box 管理面板 ===${re}"
    show_status
    echo -e "\n1) 启动 VLESS Reality"
    echo -e "2) 启动 Hysteria2 TLS"
    echo -e "3) 停止全部服务"
    echo -e "4) 查看 VLESS 日志"
    echo -e "5) 查看 Hysteria2 日志"
    echo -e "6) 查看 VLESS 配置"
    echo -e "7) 查看 Hysteria2 配置"
    echo -e "8) 退出"
    echo -n -e "${purple}请选择 [1-8]: ${re}"
}
while true; do
    show_menu
    read -r choice
    case $choice in
        1) start_vless;;
        2) start_hysteria;;
        3) stop_all;;
        4) echo -e "${green}-- VLESS 日志 (最近20行) --${re}"; tail -n20 "$LOG1" || echo -e "${yellow}日志文件不存在或为空。${re}";;
        5) echo -e "${green}-- Hysteria2 日志 (最近20行) --${re}"; tail -n20 "$LOG2" || echo -e "${yellow}日志文件不存在或为空。${re}";;
        6) echo -e "${green}-- VLESS 配置 --${re}"; head -n20 "$WORKDIR/config/vless.json";;
        7) echo -e "${green}-- Hysteria2 配置 --${re}"; head -n20 "$WORKDIR/config/hysteria2.json";;
        8) stop_all; echo -e "${green}退出管理面板。${re}"; exit 0;;
        *) echo -e "${red}无效输入，请重新选择。${re}";;
    esac
    echo -e "${yellow}按回车键继续...${re}"; read -r
done
EOF

chmod +x "$WORKDIR/menu.sh"

echo
echo -e "${green}✅ Sing-box 基础环境安装完成！${re}"
echo -e "${green}管理面板启动命令: bash $WORKDIR/menu.sh${re}"
echo
echo -e "${green}--- VLESS Reality 客户端链接 ---${re}"
echo -e "${yellow}请替换 \$DOMAIN 为您的实际域名，并确保443端口已正确映射到服务器。${re}"
echo "vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#vless_reality"
echo
echo -e "${green}--- Hysteria2 TLS 客户端链接 ---${re}"
echo -e "${yellow}请替换 \$DOMAIN 为您的实际域名，并确保30002端口已正确开放。${re}"
echo "hysteria2://$DOMAIN:$HYSTERIA2_PORT?insecure=1&password=$HYSTERIA2_PASSWORD#hysteria2_tls"
echo -e "${yellow}注意：Hysteria2 客户端需要自行导入证书 trust_ca: $WORKDIR/config/self.crt${re}"
echo
echo -e "${purple}首次运行，请执行 'bash $WORKDIR/menu.sh' 选择 1 和 2 启动服务。${re}"
