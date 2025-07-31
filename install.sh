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
USERNAME=$(whoami | tr '[:upper:]' '[:lower:]')
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
os_name=$(uname -s)
echo -e "${yellow}检测到的系统架构: $arch${re}"
echo -e "${yellow}检测到的操作系统: $os_name${re}"

if [[ "$arch" == "x86_64" || "$arch" == "amd64" ]]; then
    platform="amd64"
elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
    platform="arm64"
else
    echo -e "${red}❌ 不支持的架构: $arch${re}"
    exit 1
fi

# --- 智能端口检测和分配 ---
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

get_available_ports() {
    local tcp_ports=()
    local udp_port=""
    
    # 寻找两个可用的TCP端口
    for port in {10000..20000}; do
        if check_port $port; then
            tcp_ports+=($port)
            if [ ${#tcp_ports[@]} -eq 2 ]; then
                break
            fi
        fi
    done
    
    # 寻找一个可用的UDP端口
    for port in {20001..30000}; do
        if check_port $port; then
            udp_port=$port
            break
        fi
    done
    
    if [ ${#tcp_ports[@]} -lt 2 ] || [ -z "$udp_port" ]; then
        echo -e "${red}❌ 无法找到足够的可用端口${re}"
        exit 1
    fi
    
    export VLESS_PORT=${tcp_ports[0]}
    export VMESS_PORT=${tcp_ports[1]}
    export HY2_PORT=$udp_port
    
    echo -e "${green}选择的端口 - VLESS: $VLESS_PORT, VMESS: $VMESS_PORT, Hysteria2: $HY2_PORT${re}"
}

# --- 下载 Sing-box ---
download_singbox() {
    echo -e "${green}📦 下载 Sing-box...${re}"
    
    # 使用验证过的下载链接
    SINGBOX_URL="https://github.com/yonggekkk/Cloudflare_vless_trojan/releases/download/serv00/sb"
    SINGBOX_BIN_PATH="$BIN_DIR/sing-box"
    
    # 优先使用 curl，备用 fetch（FreeBSD）或 wget
    if command -v curl >/dev/null 2>&1; then
        curl -L -sS --max-time 30 -o "$SINGBOX_BIN_PATH" "$SINGBOX_URL" || {
            echo -e "${yellow}curl 下载失败，尝试其他方法...${re}"
            return 1
        }
    elif command -v fetch >/dev/null 2>&1; then
        fetch -o "$SINGBOX_BIN_PATH" "$SINGBOX_URL" || {
            echo -e "${yellow}fetch 下载失败，尝试其他方法...${re}"
            return 1
        }
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$SINGBOX_BIN_PATH" "$SINGBOX_URL" || {
            echo -e "${yellow}wget 下载失败${re}"
            return 1
        }
    else
        echo -e "${red}❌ 未找到可用的下载工具（curl/fetch/wget）${re}"
        exit 1
    fi
    
    if [ ! -f "$SINGBOX_BIN_PATH" ] || [ ! -s "$SINGBOX_BIN_PATH" ]; then
        echo -e "${red}❌ Sing-box 下载失败或文件为空${re}"
        return 1
    fi
    
    chmod +x "$SINGBOX_BIN_PATH"
    
    # 测试二进制文件
    echo -e "${green}🔍 测试 Sing-box 二进制文件...${re}"
    if "$SINGBOX_BIN_PATH" version >/dev/null 2>&1; then
        echo -e "${green}✅ Sing-box 二进制文件测试成功${re}"
        return 0
    else
        echo -e "${red}❌ Sing-box 二进制文件无法执行${re}"
        return 1
    fi
}

# --- 生成配置参数 ---
generate_params() {
    echo -e "${green}🔑 生成配置参数...${re}"
    
    # 生成 UUID
    if command -v uuidgen >/dev/null 2>&1; then
        UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    else
        UUID=$(openssl rand -hex 16 | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9a\10-b\11\12\13\14\15\16/')
    fi
    echo "生成的 UUID: $UUID"
    
    # 生成 Reality 密钥
    if "$BIN_DIR/sing-box" generate reality-keypair >/dev/null 2>&1; then
        KEYS=$("$BIN_DIR/sing-box" generate reality-keypair)
        PRIVATE_KEY=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')
        PUBLIC_KEY=$(echo "$KEYS" | grep PublicKey | awk '{print $2}')
    else
        # 使用预定义密钥作为备用
        echo -e "${yellow}使用预定义的 Reality 密钥...${re}"
        PRIVATE_KEY="gM7EsqnNbCnOL-TJYjg6XNHXLl5w8FG4LwGt4fKbsFs"
        PUBLIC_KEY="2FqvYBdCQFZB3fGKhrsIv9BgYhOl0GjKVv0mZaWG2n4"
    fi
    
    SHORT_ID=$(openssl rand -hex 8)
    HYSTERIA2_PASSWORD="$(openssl rand -base64 16)"
    
    echo "生成的 PrivateKey: $PRIVATE_KEY"
    echo "生成的 PublicKey: $PUBLIC_KEY"
    echo "生成的 ShortId: $SHORT_ID"
    echo "生成的 Hysteria2 密码: $HYSTERIA2_PASSWORD"
    
    # 保存参数到文件
    echo "$UUID" > "$WORKDIR/uuid.txt"
    echo "$PRIVATE_KEY" > "$WORKDIR/private_key.txt"
    echo "$PUBLIC_KEY" > "$WORKDIR/public_key.txt"
    echo "$SHORT_ID" > "$WORKDIR/short_id.txt"
    echo "$HYSTERIA2_PASSWORD" > "$WORKDIR/hy2_password.txt"
}

# --- 生成配置文件 ---
generate_configs() {
    echo -e "${green}📝 生成配置文件...${re}"
    
    # 使用更稳定的域名
    DOMAIN="www.bing.com"
    
    # 生成自签名证书
    echo -e "${green}🔐 生成自签名 TLS 证书...${re}"
    openssl req -x509 -newkey rsa:2048 -keyout "$CONFIG_DIR/self.key" -out "$CONFIG_DIR/self.crt" -days 365 -nodes -subj "/CN=$DOMAIN" >/dev/null 2>&1
    
    # 生成 VLESS Reality 配置
    cat > "$CONFIG_DIR/vless.json" << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "listen": "::",
      "listen_port": $VLESS_PORT,
      "users": [
        {
          "uuid": "$UUID",
          "flow": "xtls-rprx-vision"
        }
      ],
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
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

    # 生成 Hysteria2 配置
    cat > "$CONFIG_DIR/hysteria2.json" << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "listen": "::",
      "listen_port": $HY2_PORT,
      "users": [
        {
          "password": "$HYSTERIA2_PASSWORD"
        }
      ],
      "masquerade": "https://www.bing.com",
      "tls": {
        "enabled": true,
        "certificate": "$CONFIG_DIR/self.crt",
        "certificate_key": "$CONFIG_DIR/self.key",
        "alpn": ["h3"]
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF

    # 生成 VMESS 配置
    cat > "$CONFIG_DIR/vmess.json" << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vmess",
      "listen": "::",
      "listen_port": $VMESS_PORT,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/$UUID-vm",
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct"
    }
  ]
}
EOF
}

# --- 生成管理脚本 ---
generate_menu() {
    echo -e "${green}⚙️ 生成管理面板脚本...${re}"
    
    cat > "$WORKDIR/menu.sh" << 'MENU_EOF'
#!/usr/bin/env bash
WORKDIR="$HOME/sing-box-no-root"
BIN="$WORKDIR/bin/sing-box"
CONFIG_DIR="$WORKDIR/config"
LOG_DIR="$WORKDIR/logs"
PID_DIR="$WORKDIR/run"
mkdir -p "$PID_DIR"

re="\033[0m"
green="\e[1;32m"
red="\033[1;91m"
yellow="\e[1;33m"
purple="\e[1;35m"

# 读取保存的参数
read_params() {
    UUID=$(cat "$WORKDIR/uuid.txt" 2>/dev/null)
    PRIVATE_KEY=$(cat "$WORKDIR/private_key.txt" 2>/dev/null)
    PUBLIC_KEY=$(cat "$WORKDIR/public_key.txt" 2>/dev/null)
    SHORT_ID=$(cat "$WORKDIR/short_id.txt" 2>/dev/null)
    HYSTERIA2_PASSWORD=$(cat "$WORKDIR/hy2_password.txt" 2>/dev/null)
    VLESS_PORT=$(grep listen_port "$CONFIG_DIR/vless.json" 2>/dev/null | grep -o '[0-9]*' | head -1)
    VMESS_PORT=$(grep listen_port "$CONFIG_DIR/vmess.json" 2>/dev/null | grep -o '[0-9]*' | head -1)
    HY2_PORT=$(grep listen_port "$CONFIG_DIR/hysteria2.json" 2>/dev/null | grep -o '[0-9]*' | head -1)
}

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

start_service() {
    local service_name=$1
    local config_file=$2
    local pidfile="$PID_DIR/${service_name}.pid"
    local logfile="$LOG_DIR/${service_name}.log"
    
    if check_process "$pidfile" "$service_name"; then
        echo -e "${yellow}$service_name 已经在运行，无需重复启动。${re}"
        return 0
    fi
    
    echo -e "${green}🚀 启动 $service_name...${re}"
    
    # 检查配置文件
    if ! "$BIN" check -c "$config_file" >/dev/null 2>&1; then
        echo -e "${red}❌ $service_name 配置文件检查失败${re}"
        "$BIN" check -c "$config_file"
        return 1
    fi
    
    # 启动服务
    nohup "$BIN" run -c "$config_file" > "$logfile" 2>&1 &
    echo $! > "$pidfile"
    sleep 3
    
    if check_process "$pidfile" "$service_name"; then
        local port=$(grep listen_port "$config_file" | grep -o '[0-9]*' | head -1)
        echo -e "${green}✅ $service_name 启动成功，端口: $port，PID: $(cat "$pidfile")${re}"
        return 0
    else
        echo -e "${red}❌ $service_name 启动失败，请检查日志: $logfile${re}"
        rm -f "$pidfile"
        return 1
    fi
}

stop_all() {
    echo -e "${yellow}🛑 停止全部服务...${re}"
    local stopped_count=0
    
    for service in vless vmess hysteria2; do
        local pidfile="$PID_DIR/${service}.pid"
        if check_process "$pidfile" "$service"; then
            kill "$(cat "$pidfile")" 2>/dev/null && rm -f "$pidfile" && stopped_count=$((stopped_count+1))
            echo -e "${green}${service} 服务已停止。${re}"
        fi
    done
    
    if [ "$stopped_count" -eq 0 ]; then
        echo -e "${yellow}没有正在运行的服务需要停止。${re}"
    else
        echo -e "${green}已停止 $stopped_count 个服务。${re}"
    fi
}

show_status() {
    echo -e "\n=== 服务运行状态 ==="
    for service in vless vmess hysteria2; do
        check_process "$PID_DIR/${service}.pid" "${service^^}"
    done
    echo "======================"
}

show_links() {
    read_params
    if [ -z "$UUID" ]; then
        echo -e "${red}配置参数未找到，请重新安装${re}"
        return 1
    fi
    
    # 获取本机IP
    LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "YOUR_SERVER_IP")
    
    echo -e "${green}=== 客户端连接信息 ===${re}"
    echo -e "${yellow}服务器IP: $LOCAL_IP${re}"
    echo -e "${yellow}UUID: $UUID${re}"
    echo
    echo -e "${purple}VLESS Reality 链接：${re}"
    echo "vless://$UUID@$LOCAL_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.bing.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#vless_reality_freebsd"
    echo
    echo -e "${purple}Hysteria2 链接：${re}"
    echo "hysteria2://$HYSTERIA2_PASSWORD@$LOCAL_IP:$HY2_PORT?insecure=1#hysteria2_freebsd"
    echo
    echo -e "${purple}VMESS WebSocket 链接：${re}"
    vmess_link="{\"v\":\"2\",\"ps\":\"vmess-ws-freebsd\",\"add\":\"$LOCAL_IP\",\"port\":\"$VMESS_PORT\",\"id\":\"$UUID\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"/$UUID-vm\",\"tls\":\"\",\"sni\":\"\",\"alpn\":\"\",\"fp\":\"\"}"
    echo "vmess://$(echo "$vmess_link" | base64 -w0)"
    echo "=========================="
}

show_menu() {
    clear
    echo -e "${green}=== Sing-box 管理面板 (FreeBSD Enhanced) ===${re}"
    show_status
    echo -e "\n1) 启动 VLESS Reality"
    echo -e "2) 启动 Hysteria2"
    echo -e "3) 启动 VMESS WebSocket"
    echo -e "4) 停止全部服务"
    echo -e "5) 查看 VLESS 日志"
    echo -e "6) 查看 Hysteria2 日志"
    echo -e "7) 查看 VMESS 日志"
    echo -e "8) 显示客户端链接"
    echo -e "9) 重启所有服务"
    echo -e "0) 退出"
    echo -n -e "${purple}请选择 [0-9]: ${re}"
}

while true; do
    show_menu
    read -r choice
    case $choice in
        1) start_service "VLESS" "$CONFIG_DIR/vless.json";;
        2) start_service "Hysteria2" "$CONFIG_DIR/hysteria2.json";;
        3) start_service "VMESS" "$CONFIG_DIR/vmess.json";;
        4) stop_all;;
        5) echo -e "${green}-- VLESS 日志 (最近50行) --${re}"; tail -n50 "$LOG_DIR/vless.log" 2>/dev/null || echo -e "${yellow}日志文件不存在或为空。${re}";;
        6) echo -e "${green}-- Hysteria2 日志 (最近50行) --${re}"; tail -n50 "$LOG_DIR/hysteria2.log" 2>/dev/null || echo -e "${yellow}日志文件不存在或为空。${re}";;
        7) echo -e "${green}-- VMESS 日志 (最近50行) --${re}"; tail -n50 "$LOG_DIR/vmess.log" 2>/dev/null || echo -e "${yellow}日志文件不存在或为空。${re}";;
        8) show_links;;
        9) stop_all; sleep 2; start_service "VLESS" "$CONFIG_DIR/vless.json"; start_service "Hysteria2" "$CONFIG_DIR/hysteria2.json"; start_service "VMESS" "$CONFIG_DIR/vmess.json";;
        0) stop_all; echo -e "${green}退出管理面板。${re}"; exit 0;;
        *) echo -e "${red}无效输入，请重新选择。${re}";;
    esac
    echo -e "${yellow}按回车键继续...${re}"; read -r
done
MENU_EOF

    chmod +x "$WORKDIR/menu.sh"
}

# --- 主安装流程 ---
main() {
    # 获取可用端口
    get_available_ports
    
    # 下载 Sing-box
    if ! download_singbox; then
        echo -e "${red}❌ Sing-box 下载失败，请检查网络连接${re}"
        exit 1
    fi
    
    # 生成配置参数
    generate_params
    
    # 生成配置文件
    generate_configs
    
    # 生成管理脚本
    generate_menu
    
    echo
    echo -e "${green}✅ Sing-box FreeBSD 增强版安装完成！${re}"
    echo -e "${green}管理面板启动命令: bash $WORKDIR/menu.sh${re}"
    echo
    echo -e "${purple}主要特性：${re}"
    echo -e "${yellow}1. 智能端口分配和检测${re}"
    echo -e "${yellow}2. 三协议支持：VLESS Reality + Hysteria2 + VMESS WS${re}"
    echo -e "${yellow}3. 完整的进程管理和日志系统${re}"
    echo -e "${yellow}4. FreeBSD 系统优化${re}"
    echo -e "${yellow}5. 自动配置文件验证${re}"
    echo
    echo -e "${green}--- 端口分配信息 ---${re}"
    echo -e "${yellow}VLESS Reality 端口: $VLESS_PORT${re}"
    echo -e "${yellow}VMESS WebSocket 端口: $VMESS_PORT${re}"
    echo -e "${yellow}Hysteria2 端口: $HY2_PORT${re}"
    echo -e "${yellow}UUID: $UUID${re}"
    echo
    echo -e "${purple}现在运行管理面板: bash $WORKDIR/menu.sh${re}"
}

# 执行主函数
main
