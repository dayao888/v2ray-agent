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

# --- 架构检测 ---
arch=$(uname -m)
echo -e "${yellow}检测到的系统架构: $arch${re}"
echo -e "${yellow}检测到的操作系统: $(uname -s)${re}"

if [[ "$arch" == "x86_64" || "$arch" == "amd64" ]]; then
    platform="amd64"
elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
    platform="arm64"
else
    echo -e "${red}❌ 不支持的架构: $arch${re}"
    exit 1
fi

# --- 下载 Sing-box ---
echo -e "${green}📦 下载 Sing-box...${re}"

# 对于 FreeBSD，我们尝试下载通用的 Linux 版本或者 FreeBSD 特定版本
if uname -s | grep -qi "freebsd"; then
    echo -e "${yellow}检测到 FreeBSD 系统，下载兼容版本...${re}"
    # 首先尝试 Serv00 兼容版本
    url="https://github.com/yonggekkk/Cloudflare_vless_trojan/releases/download/serv00/sb"
else
    url="https://github.com/yonggekkk/Cloudflare_vless_trojan/releases/download/serv00/sb"
fi

SINGBOX_BIN_PATH="$BIN_DIR/sing-box"

if command -v curl >/dev/null 2>&1; then
    curl -L -o "$SINGBOX_BIN_PATH" "$url"
elif command -v fetch >/dev/null 2>&1; then
    # FreeBSD 系统通常使用 fetch 而不是 wget
    fetch -o "$SINGBOX_BIN_PATH" "$url"
elif command -v wget >/dev/null 2>&1; then
    wget -O "$SINGBOX_BIN_PATH" "$url"
else
    echo -e "${red}❌ 无法下载 Sing-box，请确保已安装 curl、fetch 或 wget。${re}"
    exit 1
fi

if [ ! -f "$SINGBOX_BIN_PATH" ]; then
    echo -e "${red}❌ Sing-box 下载失败，文件不存在: $SINGBOX_BIN_PATH${re}"
    exit 1
fi

echo -e "${green}赋予 Sing-box 执行权限...${re}"
chmod +x "$SINGBOX_BIN_PATH"

# 测试二进制文件是否可执行
echo -e "${green}测试 Sing-box 二进制文件...${re}"
if ! "$SINGBOX_BIN_PATH" version >/dev/null 2>&1; then
    echo -e "${red}❌ Sing-box 二进制文件无法执行，可能不兼容当前系统${re}"
    echo -e "${yellow}尝试下载官方版本...${re}"
    
    # 尝试下载官方版本
    OFFICIAL_URL="https://github.com/SagerNet/sing-box/releases/latest/download/sing-box-1.8.0-freebsd-${platform}.tar.gz"
    TEMP_FILE="/tmp/sing-box.tar.gz"
    
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$TEMP_FILE" "$OFFICIAL_URL" 2>/dev/null || {
            echo -e "${yellow}官方版本下载失败，继续使用当前版本...${re}"
        }
    fi
    
    if [ -f "$TEMP_FILE" ]; then
        cd "$BIN_DIR"
        tar -xzf "$TEMP_FILE" --strip-components=1
        chmod +x "$SINGBOX_BIN_PATH"
        rm -f "$TEMP_FILE"
        echo -e "${green}已替换为官方版本${re}"
    fi
fi

# --- 检查可用端口 ---
echo -e "${green}🔍 检查端口可用性...${re}"

check_port() {
    local port=$1
    if command -v sockstat >/dev/null 2>&1; then
        # FreeBSD 使用 sockstat
        if sockstat -l | grep -q ":$port "; then
            return 1  # 端口被占用
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -ln | grep -q ":$port "; then
            return 1  # 端口被占用
        fi
    fi
    return 0  # 端口可用
}

# 选择可用端口（避免特权端口和常用端口）
VLESS_PORT=8080
HYSTERIA2_PORT=8443

# 寻找可用端口
for port in 8080 8081 8082 9090 9091 9092 10080 10443; do
    if check_port $port; then
        VLESS_PORT=$port
        break
    fi
done

for port in 8443 8444 8445 9443 9444 9445 10443 10444; do
    if check_port $port; then
        HYSTERIA2_PORT=$port
        break
    fi
done

echo -e "${green}选择的端口 - VLESS: $VLESS_PORT, Hysteria2: $HYSTERIA2_PORT${re}"

# --- 生成 UUID 和 Reality 密钥 ---
echo -e "${green}🔑 生成 UUID 和 Reality 密钥...${re}"
if command -v uuidgen >/dev/null 2>&1; then
    UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
else
    # FreeBSD 兼容的 UUID 生成
    UUID=$(openssl rand -hex 16 | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9a\10-b\11\12\13\14\15\16/')
fi
echo "生成的 UUID: $UUID"

# 生成 Reality 密钥
if "$SINGBOX_BIN_PATH" generate reality-keypair >/dev/null 2>&1; then
    KEYS=$("$BIN_DIR/sing-box" generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')
    PUBLIC_KEY=$(echo "$KEYS" | grep PublicKey | awk '{print $2}')
else
    # 如果 sing-box 不支持生成密钥，使用预定义的密钥
    echo -e "${yellow}使用预定义的 Reality 密钥...${re}"
    PRIVATE_KEY="gM7EsqnNbCnOL-TJYjg6XNHXLl5w8FG4LwGt4fKbsFs"
    PUBLIC_KEY="2FqvYBdCQFZB3fGKhrsIv9BgYhOl0GjKVv0mZaWG2n4"
fi

SHORT_ID=$(openssl rand -hex 8)

echo "生成的 PrivateKey: $PRIVATE_KEY"
echo "生成的 PublicKey: $PUBLIC_KEY"
echo "生成的 ShortId: $SHORT_ID"

# --- 定义配置参数 ---
DOMAIN="www.bing.com"  # 使用更稳定的域名
HYSTERIA2_PASSWORD="$(openssl rand -base64 16)"  # 生成随机密码

echo -e "${green}📝 生成 Sing-box VLESS Reality 配置文件...${re}"
cat > "$CONFIG_DIR/vless.json" <<EOF
{
  "log": {
    "level": "info",
    "output": "$LOG_DIR/vless.log"
  },
  "inbounds": [{
    "type": "vless",
    "listen": "127.0.0.1",
    "listen_port": $VLESS_PORT,
    "users": [{
      "uuid": "$UUID",
      "flow": "xtls-rprx-vision"
    }],
    "tls": {
      "enabled": true,
      "server_name": "$DOMAIN",
      "reality": {
        "enabled": true,
        "handshake": {
          "server": "$DOMAIN",
          "server_port": 443
        },
        "private_key": "$PRIVATE_KEY",
        "short_id": ["$SHORT_ID"]
      }
    }
  }],
  "outbounds": [{
    "type": "direct"
  }]
}
EOF

echo -e "${green}📝 生成 Sing-box Hysteria2 配置文件...${re}"
echo -e "${green}🔐 生成自签名 TLS 证书...${re}"

# 生成证书
openssl req -x509 -newkey rsa:2048 -keyout "$CONFIG_DIR/self.key" -out "$CONFIG_DIR/self.crt" -days 365 -nodes -subj "/CN=$DOMAIN" >/dev/null 2>&1

cat > "$CONFIG_DIR/hysteria2.json" <<EOF
{
  "log": {
    "level": "info",
    "output": "$LOG_DIR/hysteria2.log"
  },
  "inbounds": [{
    "type": "hysteria2",
    "listen": "127.0.0.1",
    "listen_port": $HYSTERIA2_PORT,
    "users": [{
      "password": "$HYSTERIA2_PASSWORD"
    }],
    "tls": {
      "enabled": true,
      "certificate": "$CONFIG_DIR/self.crt",
      "certificate_key": "$CONFIG_DIR/self.key",
      "alpn": ["h2", "h3"]
    }
  }],
  "outbounds": [{
    "type": "direct"
  }]
}
EOF

# --- 生成管理菜单脚本 ---
echo -e "${green}⚙️ 生成管理面板脚本...${re}"

cat > "$WORKDIR/menu.sh" <<'MENU_EOF'
#!/usr/bin/env bash
WORKDIR="$HOME/sing-box-no-root"
BIN="$WORKDIR/bin/sing-box"
LOG1="$WORKDIR/logs/vless.log"
LOG2="$WORKDIR/logs/hysteria2.log"
PID_DIR="$WORKDIR/run"
mkdir -p "$PID_DIR"
pidfile1="$PID_DIR/vless.pid"
pidfile2="$PID_DIR/hysteria2.pid"

re="\033[0m"
green="\e[1;32m"
red="\033[1;91m"
yellow="\e[1;33m"
purple="\e[1;35m"

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
    
    # 检查配置文件
    if ! "$BIN" check -c "$WORKDIR/config/vless.json" >/dev/null 2>&1; then
        echo -e "${red}❌ VLESS 配置文件检查失败${re}"
        "$BIN" check -c "$WORKDIR/config/vless.json"
        return 1
    fi
    
    nohup "$BIN" run -c "$WORKDIR/config/vless.json" >/dev/null 2>&1 &
    echo $! > "$pidfile1"
    sleep 2
    if check_process "$pidfile1" "VLESS"; then
        port=$(grep listen_port "$WORKDIR/config/vless.json" | grep -o '[0-9]*')
        echo -e "${green}✅ VLESS 启动成功，端口: $port，PID: $(cat $pidfile1)${re}"
    else
        echo -e "${red}❌ VLESS 启动失败，请检查日志: $LOG1${re}"
        rm -f "$pidfile1"
    fi
}

start_hysteria(){
    if check_process "$pidfile2" "Hysteria2"; then
        echo -e "${yellow}Hysteria2 已经在运行，无需重复启动。${re}"
        return
    fi
    echo -e "${green}🚀 启动 Hysteria2 TLS...${re}"
    
    # 检查配置文件
    if ! "$BIN" check -c "$WORKDIR/config/hysteria2.json" >/dev/null 2>&1; then
        echo -e "${red}❌ Hysteria2 配置文件检查失败${re}"
        "$BIN" check -c "$WORKDIR/config/hysteria2.json"
        return 1
    fi
    
    nohup "$BIN" run -c "$WORKDIR/config/hysteria2.json" >/dev/null 2>&1 &
    echo $! > "$pidfile2"
    sleep 2
    if check_process "$pidfile2" "Hysteria2"; then
        port=$(grep listen_port "$WORKDIR/config/hysteria2.json" | grep -o '[0-9]*')
        echo -e "${green}✅ Hysteria2 启动成功，端口: $port，PID: $(cat $pidfile2)${re}"
    else
        echo -e "${red}❌ Hysteria2 启动失败，请检查日志: $LOG2${re}"
        rm -f "$pidfile2"
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

show_links(){
    if [ -f "$WORKDIR/config/vless.json" ] && [ -f "$WORKDIR/config/hysteria2.json" ]; then
        echo -e "${green}=== 客户端连接信息 ===${re}"
        echo -e "${yellow}VLESS Reality 链接：${re}"
        cat "$WORKDIR/vless_link.txt" 2>/dev/null || echo "链接文件不存在"
        echo
        echo -e "${yellow}Hysteria2 链接：${re}"
        cat "$WORKDIR/hysteria2_link.txt" 2>/dev/null || echo "链接文件不存在"
        echo "=========================="
    fi
}

show_menu(){
    clear;
    echo -e "${green}=== Sing-box 管理面板 (FreeBSD) ===${re}"
    show_status
    echo -e "\n1) 启动 VLESS Reality"
    echo -e "2) 启动 Hysteria2 TLS"
    echo -e "3) 停止全部服务"
    echo -e "4) 查看 VLESS 日志"
    echo -e "5) 查看 Hysteria2 日志"
    echo -e "6) 查看 VLESS 配置"
    echo -e "7) 查看 Hysteria2 配置"
    echo -e "8) 显示客户端链接"
    echo -e "9) 退出"
    echo -n -e "${purple}请选择 [1-9]: ${re}"
}

while true; do
    show_menu
    read -r choice
    case $choice in
        1) start_vless;;
        2) start_hysteria;;
        3) stop_all;;
        4) echo -e "${green}-- VLESS 日志 (最近30行) --${re}"; tail -n30 "$LOG1" 2>/dev/null || echo -e "${yellow}日志文件不存在或为空。${re}";;
        5) echo -e "${green}-- Hysteria2 日志 (最近30行) --${re}"; tail -n30 "$LOG2" 2>/dev/null || echo -e "${yellow}日志文件不存在或为空。${re}";;
        6) echo -e "${green}-- VLESS 配置 --${re}"; cat "$WORKDIR/config/vless.json" | head -n30;;
        7) echo -e "${green}-- Hysteria2 配置 --${re}"; cat "$WORKDIR/config/hysteria2.json" | head -n30;;
        8) show_links;;
        9) stop_all; echo -e "${green}退出管理面板。${re}"; exit 0;;
        *) echo -e "${red}无效输入，请重新选择。${re}";;
    esac
    echo -e "${yellow}按回车键继续...${re}"; read -r
done
MENU_EOF

chmod +x "$WORKDIR/menu.sh"

# --- 生成客户端链接文件 ---
echo -e "${green}📱 生成客户端链接...${re}"

# 获取本机 IP 地址
if command -v ifconfig >/dev/null 2>&1; then
    LOCAL_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -n1 | awk '{print $2}')
else
    LOCAL_IP="YOUR_SERVER_IP"
fi

# 生成 VLESS 链接
echo "vless://$UUID@$LOCAL_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#vless_reality_freebsd" > "$WORKDIR/vless_link.txt"

# 生成 Hysteria2 链接
echo "hysteria2://$HYSTERIA2_PASSWORD@$LOCAL_IP:$HYSTERIA2_PORT?insecure=1#hysteria2_freebsd" > "$WORKDIR/hysteria2_link.txt"

echo
echo -e "${green}✅ Sing-box FreeBSD 兼容版本安装完成！${re}"
echo -e "${green}管理面板启动命令: bash $WORKDIR/menu.sh${re}"
echo
echo -e "${purple}主要改进：${re}"
echo -e "${yellow}1. 监听地址改为 127.0.0.1 (本地回环)${re}"
echo -e "${yellow}2. 使用非特权端口 ($VLESS_PORT, $HYSTERIA2_PORT)${re}"
echo -e "${yellow}3. 添加了 FreeBSD 兼容性检查${re}"
echo -e "${yellow}4. 改进了端口可用性检测${re}"
echo -e "${yellow}5. 添加了配置文件验证${re}"
echo
echo -e "${green}--- 客户端连接信息 ---${re}"
echo -e "${yellow}本机 IP: $LOCAL_IP${re}"
echo -e "${yellow}VLESS 端口: $VLESS_PORT${re}"
echo -e "${yellow}Hysteria2 端口: $HYSTERIA2_PORT${re}"
echo -e "${yellow}Hysteria2 密码: $HYSTERIA2_PASSWORD${re}"
echo
echo -e "${purple}现在运行: bash $WORKDIR/menu.sh${re}"
