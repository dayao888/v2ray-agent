#!/usr/bin/env bash
set -e

# --- 辅助函数和变量定义 ---
# 颜色定义
re="\033[0m"
red="\033[1;91m"
green="\e[1;32m"
yellow="\e[1;33m"
purple="\e[1;35m"

# 封装打印函数
red() { echo -e "\e[1;91m$1\033[0m"; }
green() { echo -e "\e[1;32m$1\033[0m"; }
yellow() { echo -e "\e[1;33m$1\033[0m"; }
purple() { echo -e "\e[1;35m$1\033[0m"; }
reading() { read -p "$(purple "$1")" "$2"; }

# 工作目录定义
WORKDIR="$HOME/sing-box-no-root"
BIN_DIR="$WORKDIR/bin"
CONFIG_DIR="$WORKDIR/config"
LOG_DIR="$WORKDIR/logs"
RUN_DIR="$WORKDIR/run"

# --- 智能端口检测和分配 ---
check_port() {
    local port=$1
    # 优先使用 lsof，兼容性更好
    if command -v lsof >/dev/null 2>&1; then
        if lsof -i :$port -sTCP:LISTEN -sUDP:LISTEN >/dev/null; then
            return 1 # 端口被占用
        fi
    # 兼容 FreeBSD 的 sockstat
    elif command -v sockstat >/dev/null 2>&1; then
        if sockstat -l | grep -q ":$port "; then
            return 1 # 端口被占用
        fi
    # 兼容 Linux 的 netstat
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -lntu | grep -q ":$port "; then
            return 1 # 端口被占用
        fi
    fi
    return 0 # 端口可用
}

get_available_ports() {
    green "🔍 正在智能检测并分配可用端口..."
    local tcp_ports=()
    local udp_port=""
    local found_tcp=0
    local found_udp=0
    
    # 从随机范围寻找端口，以减少冲突
    for i in {1..100}; do
        if [ "$found_tcp" -lt 2 ]; then
            local p_tcp=$(shuf -i 10000-30000 -n 1)
            if check_port "$p_tcp"; then
                tcp_ports+=($p_tcp)
                ((found_tcp++))
            fi
        fi
        
        if [ "$found_udp" -eq 0 ]; then
            local p_udp=$(shuf -i 30001-60000 -n 1)
            if check_port "$p_udp"; then
                udp_port=$p_udp
                ((found_udp++))
            fi
        fi

        if [ "$found_tcp" -eq 2 ] && [ "$found_udp" -eq 1 ]; then
            break
        fi
    done
    
    if [ ${#tcp_ports[@]} -lt 2 ] || [ -z "$udp_port" ]; then
        red "❌ 无法找到足够的可用端口，请检查系统端口占用情况。"
        exit 1
    fi
    
    # 使用 export 使这些变量在整个脚本的子进程中都可用
    export VLESS_PORT=${tcp_ports[0]}
    export VMESS_PORT=${tcp_ports[1]}
    export HY2_PORT=$udp_port
    
    green "✅ 端口分配成功！"
    echo -e "${yellow}   - VLESS Reality (TCP): $VLESS_PORT${re}"
    echo -e "${yellow}   - VMESS WebSocket (TCP): $VMESS_PORT${re}"
    echo -e "${yellow}   - Hysteria2 (UDP): $HY2_PORT${re}"
}


# --- 下载 Sing-box ---
download_singbox() {
    echo -e "${green}📦 正在下载 Sing-box 核心文件...${re}"
    
    # 这个链接是经过验证的，比较稳定
    SINGBOX_URL="https://github.com/yonggekkk/Cloudflare_vless_trojan/releases/download/serv00/sb"
    SINGBOX_BIN_PATH="$BIN_DIR/sing-box"
    
    # 优先使用 curl，备用 fetch（FreeBSD）或 wget
    if command -v curl >/dev/null 2>&1; then
        if ! curl -L -sS --max-time 60 -o "$SINGBOX_BIN_PATH" "$SINGBOX_URL"; then
            yellow "curl 下载失败，尝试使用 wget..."
            if ! command -v wget >/dev/null 2>&1 || ! wget -O "$SINGBOX_BIN_PATH" "$SINGBOX_URL"; then
                red "❌ 所有下载方式均失败。"
                return 1
            fi
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -O "$SINGBOX_BIN_PATH" "$SINGBOX_URL"; then
             red "❌ wget 下载失败。"
             return 1
        fi
    else
        red "❌ 未找到可用的下载工具（curl/wget）。"
        exit 1
    fi
    
    if [ ! -f "$SINGBOX_BIN_PATH" ] || [ ! -s "$SINGBOX_BIN_PATH" ]; then
        red "❌ Sing-box 下载失败或文件为空。"
        return 1
    fi
    
    chmod +x "$SINGBOX_BIN_PATH"
    
    # 测试二进制文件
    echo -e "${green}🔬 正在测试 Sing-box 核心文件...${re}"
    if "$SINGBOX_BIN_PATH" version >/dev/null 2>&1; then
        green "✅ Sing-box 核心文件测试成功！"
        return 0
    else
        red "❌ Sing-box 核心文件无法执行，可能与系统架构不兼容。"
        return 1
    fi
}

# --- 生成配置参数 ---
generate_params() {
    green "🔑 正在生成加密参数和密钥..."
    
    # 生成 UUID
    if command -v uuidgen >/dev/null 2>&1; then
        UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    else
        UUID=$(od -x /dev/urandom | head -1 | awk '{OFS="-"; print $2$3,$4,$5,$6,$7$8$9}')
    fi
    
    # 生成 Reality 密钥
    KEYS=$("$BIN_DIR/sing-box" generate reality-keypair)
    PRIVATE_KEY=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}' | tr -d '"')
    PUBLIC_KEY=$(echo "$KEYS" | grep PublicKey | awk '{print $2}' | tr -d '"')
    
    SHORT_ID=$(openssl rand -hex 8)
    HYSTERIA2_PASSWORD=$(openssl rand -base64 16)
    
    green "✅ 参数生成完毕！"
    
    # 保存参数到文件以便后续使用
    echo "$UUID" > "$WORKDIR/uuid.txt"
    echo "$PRIVATE_KEY" > "$WORKDIR/private_key.txt"
    echo "$PUBLIC_KEY" > "$WORKDIR/public_key.txt"
    echo "$SHORT_ID" > "$WORKDIR/short_id.txt"
    echo "$HYSTERIA2_PASSWORD" > "$WORKDIR/hy2_password.txt"
}

# --- 生成统一的配置文件 ---
generate_unified_config() {
    green "📝 正在生成统一的配置文件..."
    
    DOMAIN="www.bing.com"
    
    green "🔐 正在生成自签名 TLS 证书..."
    openssl req -x509 -newkey rsa:2048 -keyout "$CONFIG_DIR/self.key" -out "$CONFIG_DIR/self.crt" -days 3650 -nodes -subj "/CN=$DOMAIN" >/dev/null 2>&1
    
    # 使用 Heredoc 创建统一的 JSON 配置文件
    cat > "$CONFIG_DIR/config.json" << EOF
{
  "log": {
    "disabled": false,
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-in",
      "listen": "::",
      "listen_port": $VLESS_PORT,
      "sniff": true,
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
    },
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $HY2_PORT,
      "sniff": true,
      "users": [
        {
          "password": "$HYSTERIA2_PASSWORD"
        }
      ],
      "masquerade": "https://www.bing.com",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "$CONFIG_DIR/self.crt",
        "key_path": "$CONFIG_DIR/self.key"
      }
    },
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "::",
      "listen_port": $VMESS_PORT,
      "sniff": true,
      "users": [
        {
          "uuid": "$UUID"
        }
      ],
      "transport": {
        "type": "ws",
        "path": "/${UUID}-vm",
        "early_data_header_name": "Sec-WebSocket-Protocol"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ],
  "route": {
    "final": "direct"
  }
}
EOF
    green "✅ 配置文件 'config.json' 创建成功！"
}

# --- 生成管理脚本 ---
generate_management_script() {
    green "⚙️ 正在创建便捷管理脚本 'sb.sh'..."
    
    cat > "$WORKDIR/sb.sh" << 'MENU_EOF'
#!/usr/bin/env bash
# 获取脚本所在目录，确保路径正确
WORKDIR=$(dirname "$(readlink -f "$0")")
BIN="$WORKDIR/bin/sing-box"
CONFIG_FILE="$WORKDIR/config/config.json"
LOG_FILE="$WORKDIR/logs/sing-box.log"
PID_FILE="$WORKDIR/run/sing-box.pid"
mkdir -p "$WORKDIR/run"

# 颜色定义
re="\033[0m"
green="\e[1;32m"
red="\033[1;91m"
yellow="\e[1;33m"
purple="\e[1;35m"

# 从文件中读取保存的参数
read_params() {
    UUID=$(cat "$WORKDIR/uuid.txt" 2>/dev/null)
    PUBLIC_KEY=$(cat "$WORKDIR/public_key.txt" 2>/dev/null)
    SHORT_ID=$(cat "$WORKDIR/short_id.txt" 2>/dev/null)
    HYSTERIA2_PASSWORD=$(cat "$WORKDIR/hy2_password.txt" 2>/dev/null)
    # 从统一的配置文件中解析端口
    VLESS_PORT=$(grep -A 6 '"tag": "vless-in"' "$CONFIG_FILE" 2>/dev/null | grep listen_port | grep -o '[0-9]*' | head -1)
    VMESS_PORT=$(grep -A 6 '"tag": "vmess-in"' "$CONFIG_FILE" 2>/dev/null | grep listen_port | grep -o '[0-9]*' | head -1)
    HY2_PORT=$(grep -A 6 '"tag": "hy2-in"' "$CONFIG_FILE" 2>/dev/null | grep listen_port | grep -o '[0-9]*' | head -1)
}

# 检查 sing-box 进程是否在运行
check_process() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        return 0 # 正在运行
    else
        return 1 # 未运行
    fi
}

# 启动 sing-box 服务
start_service() {
    if check_process; then
        echo -e "${yellow}Sing-box 已经在运行 (PID: $(cat "$PID_FILE"))${re}"
        return
    fi
    
    echo -e "${green}🚀 启动 Sing-box...${re}"
    
    # 启动前检查配置文件语法
    if ! "$BIN" check -c "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${red}❌ Sing-box 配置文件检查失败，请检查 'config.json'。${re}"
        "$BIN" check -c "$CONFIG_FILE"
        return
    fi
    
    # 使用 nohup 后台运行
    nohup "$BIN" run -c "$CONFIG_FILE" > "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 2 # 等待进程启动
    
    if check_process; then
        echo -e "${green}✅ Sing-box 启动成功 (PID: $(cat "$PID_FILE"))${re}"
    else
        echo -e "${red}❌ Sing-box 启动失败，请查看日志: $LOG_FILE${re}"
        rm -f "$PID_FILE"
    fi
}

# 停止 sing-box 服务
stop_service() {
    if check_process; then
        echo -e "${yellow}🛑 停止 Sing-box...${re}"
        kill "$(cat "$PID_FILE")" 2>/dev/null
        rm -f "$PID_FILE"
        echo -e "${green}Sing-box 服务已停止。${re}"
    else
        echo -e "${red}Sing-box 未运行。${re}"
    fi
}

# 显示客户端连接链接
show_links() {
    read_params
    if [ -z "$UUID" ]; then
        echo -e "${red}配置参数未找到，请尝试重新安装。${re}"
        return
    fi
    
    # 尝试获取服务器公网 IP
    if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
        LOCAL_IP=$(hostname -I | awk '{print $1}')
    else
        LOCAL_IP="YOUR_SERVER_IP" # 备用提示
    fi
    
    echo -e "\n${green}=== 客户端连接信息 ===${re}"
    echo -e "${yellow}服务器IP: $LOCAL_IP (如果不正确，请手动替换为你的公网IP)${re}"
    echo -e "${yellow}通用 UUID: $UUID${re}"
    echo
    echo -e "${purple}VLESS Reality 链接：${re}"
    echo "vless://$UUID@$LOCAL_IP:$VLESS_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.bing.com&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#VLESS-Reality"
    echo
    echo -e "${purple}Hysteria2 链接：${re}"
    echo "hysteria2://$HYSTERIA2_PASSWORD@$LOCAL_IP:$HY2_PORT?insecure=1&sni=www.bing.com#Hysteria2"
    echo
    echo -e "${purple}VMESS WebSocket 链接：${re}"
    vmess_link_json="{\"v\":\"2\",\"ps\":\"VMESS-WS\",\"add\":\"$LOCAL_IP\",\"port\":\"$VMESS_PORT\",\"id\":\"$UUID\",\"aid\":\"0\",\"scy\":\"auto\",\"net\":\"ws\",\"type\":\"none\",\"host\":\"\",\"path\":\"/${UUID}-vm\",\"tls\":\"\",\"sni\":\"\",\"alpn\":\"\",\"fp\":\"\"}"
    echo "vmess://$(echo -n "$vmess_link_json" | base64 | tr -d '\n')"
    echo -e "\n=========================="
}

# 主菜单
main_menu() {
    clear
    echo -e "${green}=== Sing-box 管理面板 (No-Root Enhanced) ===${re}"
    if check_process; then
        echo -e "${green}状态: 正在运行 (PID: $(cat "$PID_FILE"))${re}"
    else
        echo -e "${red}状态: 未运行${re}"
    fi
    echo -e "============================================="
    echo -e " 1) 启动 Sing-box"
    echo -e " 2) 停止 Sing-box"
    echo -e " 3) 重启 Sing-box"
    echo -e " 4) 查看运行日志"
    echo -e " 5) 显示客户端链接"
    echo -e " 6) 卸载"
    echo -e " 0) 退出"
    echo -e "============================================="
    read -p "$(echo -e "${purple}请选择 [0-6]: ${re}")" choice
    
    case $choice in
        1) start_service;;
        2) stop_service;;
        3) stop_service; sleep 1; start_service;;
        4) echo -e "${green}-- Sing-box 日志 (最近50行) --${re}"; tail -n 50 "$LOG_FILE" 2>/dev/null || echo -e "${yellow}日志文件不存在或为空。${re}";;
        5) show_links;;
        6) 
            read -p "$(echo -e "${red}确定要卸载吗? 这将删除所有相关文件。[y/N]: ${re}")" confirm
            if [[ "$confirm" =~ ^[yY]$ ]]; then
                stop_service
                echo -e "${red}正在卸载...${re}"
                rm -rf "$WORKDIR"
                echo -e "${green}卸载完成。${re}"
                exit 0
            fi
            ;;
        0) exit 0;;
        *) echo -e "${red}无效输入，请重新选择。${re}";;
    esac
    echo -e "\n${yellow}按回车键返回主菜单...${re}"; read -r
}

# 循环显示主菜单
while true; do
    main_menu
done
MENU_EOF

    chmod +x "$WORKDIR/sb.sh"
    green "✅ 管理脚本 'sb.sh' 创建成功！"
}

# --- 主安装流程 ---
main() {
    clear
    purple "=== 欢迎使用 Sing-box (No-Root Enhanced) 一键安装脚本 ==="

    echo -e "\n${green}🧹 正在清理旧的安装目录 (如果存在)...${re}"
    rm -rf "$WORKDIR"

    echo -e "${green}📁 正在创建工作目录结构...${re}"
    mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$RUN_DIR"

    # 执行核心安装步骤
    get_available_ports
    if ! download_singbox; then
        red "❌ 安装失败：Sing-box 核心下载失败。"
        exit 1
    fi
    generate_params
    generate_unified_config
    generate_management_script
    
    # 结束语
    echo
    green "🎉🎉🎉 Sing-box (No-Root Enhanced) 安装成功！🎉🎉🎉"
    purple "--------------------------------------------------------"
    echo
    yellow "您现在可以通过以下命令来管理 Sing-box 服务:"
    purple "   bash $WORKDIR/sb.sh"
    echo
    yellow "为了方便，您可以创建一个别名:"
    purple "   echo \"alias sb='bash $WORKDIR/sb.sh'\" >> ~/.bash_profile && source ~/.bash_profile"
    echo
    yellow "然后就可以直接使用 'sb' 命令来启动管理面板了。"
    echo
    purple "--------------------------------------------------------"
    
    # 自动启动管理面板
    bash "$WORKDIR/sb.sh"
}

# --- 脚本执行入口 ---
main
