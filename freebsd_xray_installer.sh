#!/bin/sh
# FreeBSD Xray安装脚本 - 无需root权限版本
# 适用于FreeBSD 14.1 amd64架构

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 工作目录
WORK_DIR="$HOME/xray-freebsd"
BIN_DIR="$WORK_DIR/bin"
CONFIG_DIR="$WORK_DIR/config"
LOG_DIR="$WORK_DIR/logs"
RUN_DIR="$WORK_DIR/run"

# 打印彩色文本
print_color() {
    case "$1" in
        "red") printf "${RED}%s${PLAIN}\n" "$2" ;;
        "green") printf "${GREEN}%s${PLAIN}\n" "$2" ;;
        "yellow") printf "${YELLOW}%s${PLAIN}\n" "$2" ;;
        "blue") printf "${BLUE}%s${PLAIN}\n" "$2" ;;
    esac
}

# 检查系统
check_system() {
    if [ "$(uname -s)" != "FreeBSD" ]; then
        print_color "red" "错误: 此脚本仅适用于FreeBSD系统"
        exit 1
    fi
    
    if [ "$(uname -m)" != "amd64" ]; then
        print_color "yellow" "警告: 此脚本针对amd64架构优化，在当前架构($(uname -m))上可能存在兼容性问题"
    fi
    
    print_color "green" "系统检测通过: FreeBSD $(uname -r) $(uname -m)"
}

# 检查依赖
check_dependencies() {
    print_color "blue" "检查必要依赖..."
    
    # 检查并安装必要的工具
    for cmd in curl jq openssl unzip; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            print_color "yellow" "未找到 $cmd，尝试安装..."
            pkg install -y "$cmd" || {
                print_color "red" "无法安装 $cmd，请手动安装后重试"
                print_color "yellow" "提示: 可以使用 'pkg install -y $cmd' 命令安装"
                exit 1
            }
        fi
    done
    
    print_color "green" "所有依赖已满足"
}

# 创建工作目录
create_directories() {
    print_color "blue" "创建工作目录..."
    mkdir -p "$BIN_DIR" "$CONFIG_DIR" "$LOG_DIR" "$RUN_DIR"
    print_color "green" "工作目录创建完成"
}

# 下载Xray-core
download_xray() {
    print_color "blue" "下载Xray-core..."
    
    # 使用新版本v25.5.16
    XRAY_VERSION="v25.5.16"
    print_color "green" "使用Xray版本: $XRAY_VERSION"
    
    # 下载Xray
    XRAY_FILE="Xray-freebsd-64.zip"
    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/$XRAY_VERSION/$XRAY_FILE"
    
    print_color "blue" "下载Xray: $DOWNLOAD_URL"
    if ! curl -L -o "/tmp/$XRAY_FILE" "$DOWNLOAD_URL"; then
        print_color "red" "下载Xray失败"
        exit 1
    fi
    
    # 解压
    print_color "blue" "解压Xray..."
    if ! unzip -o "/tmp/$XRAY_FILE" -d "/tmp/xray-temp"; then
        print_color "red" "解压Xray失败"
        exit 1
    fi
    
    # 移动文件
    cp "/tmp/xray-temp/xray" "$BIN_DIR/xray"
    chmod +x "$BIN_DIR/xray"
    
    # 清理临时文件
    rm -rf "/tmp/xray-temp" "/tmp/$XRAY_FILE"
    
    # 验证安装
    if [ ! -f "$BIN_DIR/xray" ]; then
        print_color "red" "Xray安装失败"
        exit 1
    fi
    
    print_color "green" "Xray-core $XRAY_VERSION 安装成功"
}

# 检测可用端口
check_port_available() {
    local port=$1
    if netstat -an | grep -q ":$port "; then
        return 1  # 端口被占用
    else
        return 0  # 端口可用
    fi
}

# 生成或选择可用端口
generate_port() {
    # 优先使用用户系统的开放端口
    local preferred_ports="27341 44486 52098"
    
    for port in $preferred_ports; do
        if check_port_available "$port"; then
            echo "$port"
            return
        fi
    done
    
    # 如果首选端口都被占用，生成随机端口
    local attempts=0
    while [ $attempts -lt 10 ]; do
        local random_port=$((RANDOM % 55535 + 10000))
        if check_port_available "$random_port"; then
            echo "$random_port"
            return
        fi
        attempts=$((attempts + 1))
    done
    
    # 如果都失败，使用默认端口
    echo "10086"
}

# 生成UUID
generate_uuid() {
    "$BIN_DIR/xray" uuid
}

# 生成Reality密钥对
generate_reality_keypair() {
    "$BIN_DIR/xray" x25519
}

# 配置Xray
configure_xray() {
    print_color "blue" "配置Xray..."
    
    # 生成随机端口
    XRAY_PORT=$(generate_port)
    print_color "green" "已选择端口: $XRAY_PORT"
    
    # 生成UUID
    UUID=$(generate_uuid)
    print_color "green" "已生成UUID: $UUID"
    
    # 生成Reality密钥对
    KEYPAIR=$(generate_reality_keypair)
    PRIVATE_KEY=$(echo "$KEYPAIR" | grep "Private" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEYPAIR" | grep "Public" | awk '{print $3}')
    print_color "green" "已生成Reality密钥对"
    print_color "green" "Private Key: $PRIVATE_KEY"
    print_color "green" "Public Key: $PUBLIC_KEY"
    
    # 生成多个短ID以增强安全性
    SHORT_ID1=$(openssl rand -hex 8)
    SHORT_ID2=$(openssl rand -hex 4)
    SHORT_ID3=$(openssl rand -hex 2)
    print_color "green" "已生成Short IDs: $SHORT_ID1, $SHORT_ID2, $SHORT_ID3"
    
    # 随机选择伪装域名以降低特征识别
    FAKE_DOMAINS="www.microsoft.com www.apple.com www.cloudflare.com www.github.com www.stackoverflow.com www.reddit.com"
    DOMAIN_COUNT=$(echo $FAKE_DOMAINS | wc -w)
    DOMAIN_INDEX=$((RANDOM % DOMAIN_COUNT + 1))
    FAKE_DOMAIN=$(echo $FAKE_DOMAINS | cut -d' ' -f$DOMAIN_INDEX)
    print_color "green" "已选择伪装域名: $FAKE_DOMAIN"
    
    # 创建配置文件
    cat > "$CONFIG_DIR/config.json" << EOF
{
  "log": {
    "loglevel": "warning",
    "access": "$LOG_DIR/access.log",
    "error": "$LOG_DIR/error.log"
  },
  "inbounds": [
    {
      "port": $XRAY_PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none",
        "fallbacks": [
          {
            "dest": "$FAKE_DOMAIN:443",
            "xver": 1
          }
        ]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$FAKE_DOMAIN:443",
          "serverNames": [
            "$FAKE_DOMAIN",
            "*.$(echo $FAKE_DOMAIN | cut -d'.' -f2-)"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID1",
            "$SHORT_ID2",
            "$SHORT_ID3",
            ""
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct",
      "settings": {
        "domainStrategy": "UseIPv4"
      }
    },
    {
      "protocol": "blackhole",
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "domain": [
          "geosite:category-ads-all"
        ],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "blocked"
      },
      {
        "type": "field",
        "ip": [
          "geoip:cn"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": [
          "geosite:cn"
        ],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF

    print_color "green" "Xray配置文件已生成: $CONFIG_DIR/config.json"
    
    # 获取服务器IP地址（使用多个API以提高成功率）
    print_color "blue" "获取服务器IP地址..."
    SERVER_IP=$(curl -s --connect-timeout 10 https://api.ipify.org 2>/dev/null || \
                curl -s --connect-timeout 10 https://ifconfig.me 2>/dev/null || \
                curl -s --connect-timeout 10 https://icanhazip.com 2>/dev/null || \
                curl -s --connect-timeout 10 https://ident.me 2>/dev/null)
    
    if [ -z "$SERVER_IP" ]; then
        print_color "yellow" "警告: 无法获取服务器IP地址，尝试本地检测..."
        # 尝试从网络接口获取IP
        SERVER_IP=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')
        if [ -z "$SERVER_IP" ]; then
            print_color "red" "无法获取IP地址，请手动替换连接信息中的SERVER_IP部分"
            SERVER_IP="YOUR_SERVER_IP"
        else
            print_color "yellow" "使用本地检测到的IP: $SERVER_IP"
        fi
    else
        print_color "green" "检测到服务器IP: $SERVER_IP"
    fi
    
    # 生成V2Ray链接（使用第一个短ID）
    VLESS_LINK="vless://$UUID@$SERVER_IP:$XRAY_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$FAKE_DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID1&type=tcp&headerType=none#FreeBSD-VLESS-Reality-Enhanced"
    
    echo "$VLESS_LINK" > "$CONFIG_DIR/client_link.txt"
    
    # 生成备用连接信息（使用不同的短ID）
    VLESS_LINK2="vless://$UUID@$SERVER_IP:$XRAY_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$FAKE_DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID2&type=tcp&headerType=none#FreeBSD-VLESS-Reality-Backup"
    echo "$VLESS_LINK2" >> "$CONFIG_DIR/client_link.txt"
    
    print_color "green" "客户端连接信息已保存至: $CONFIG_DIR/client_link.txt"
    
    # 安全提示
    print_color "yellow" "=== 安全建议 ==="
    print_color "blue" "1. 建议定期更换端口和UUID以提高安全性"
    print_color "blue" "2. 避免在高峰时段大量使用以降低被检测风险"
    print_color "blue" "3. 建议配置防火墙只允许必要的端口访问"
    print_color "blue" "4. 定期检查日志文件，监控异常连接"
}

# 创建管理脚本
create_management_script() {
    print_color "blue" "创建管理脚本..."
    
    cat > "$WORK_DIR/menu.sh" << 'EOF'
#!/bin/sh

# 工作目录
WORK_DIR="$HOME/xray-freebsd"
BIN_DIR="$WORK_DIR/bin"
CONFIG_DIR="$WORK_DIR/config"
LOG_DIR="$WORK_DIR/logs"
RUN_DIR="$WORK_DIR/run"
PID_FILE="$RUN_DIR/xray.pid"

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

# 打印彩色文本
print_color() {
    case "$1" in
        "red") printf "${RED}%s${PLAIN}\n" "$2" ;;
        "green") printf "${GREEN}%s${PLAIN}\n" "$2" ;;
        "yellow") printf "${YELLOW}%s${PLAIN}\n" "$2" ;;
        "blue") printf "${BLUE}%s${PLAIN}\n" "$2" ;;
    esac
}

# 检查Xray是否运行
check_running() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# 启动Xray
start_xray() {
    if check_running; then
        print_color "yellow" "Xray已经在运行中，PID: $(cat "$PID_FILE")"
        return
    fi
    
    # 检查配置文件
    if [ ! -f "$CONFIG_DIR/config.json" ]; then
        print_color "red" "配置文件不存在: $CONFIG_DIR/config.json"
        return 1
    fi
    
    # 验证配置文件
    print_color "blue" "验证配置文件..."
    if ! "$BIN_DIR/xray" test -c "$CONFIG_DIR/config.json" > "$LOG_DIR/config_test.log" 2>&1; then
        print_color "red" "配置文件验证失败，请检查: $LOG_DIR/config_test.log"
        return 1
    fi
    
    print_color "blue" "启动Xray..."
    cd "$WORK_DIR" || exit 1
    
    # 使用更详细的日志记录
    nohup "$BIN_DIR/xray" run -c "$CONFIG_DIR/config.json" > "$LOG_DIR/stdout.log" 2>&1 &
    local xray_pid=$!
    echo $xray_pid > "$PID_FILE"
    
    # 等待更长时间确保启动完成
    sleep 3
    
    if check_running; then
        print_color "green" "Xray启动成功，PID: $xray_pid"
        # 显示监听端口
        local port=$(grep -o '"port": [0-9]*' "$CONFIG_DIR/config.json" | head -1 | awk '{print $2}')
        print_color "blue" "监听端口: $port"
    else
        print_color "red" "Xray启动失败，请检查日志:"
        print_color "yellow" "配置测试: $LOG_DIR/config_test.log"
        print_color "yellow" "运行日志: $LOG_DIR/stdout.log"
        print_color "yellow" "错误日志: $LOG_DIR/error.log"
        return 1
    fi
}

# 停止Xray
stop_xray() {
    if ! check_running; then
        print_color "yellow" "Xray未在运行"
        return
    fi
    
    print_color "blue" "停止Xray..."
    PID=$(cat "$PID_FILE")
    kill "$PID"
    rm -f "$PID_FILE"
    
    print_color "green" "Xray已停止"
}

# 重启Xray
restart_xray() {
    stop_xray
    sleep 1
    start_xray
}

# 查看Xray状态
status_xray() {
    if check_running; then
        print_color "green" "Xray正在运行，PID: $(cat "$PID_FILE")"
        print_color "blue" "配置文件: $CONFIG_DIR/config.json"
        print_color "blue" "日志文件: $LOG_DIR/access.log, $LOG_DIR/error.log"
        
        # 显示监听端口
        PORT=$(grep -o '"port": [0-9]*' "$CONFIG_DIR/config.json" | awk '{print $2}')
        print_color "blue" "监听端口: $PORT"
    else
        print_color "yellow" "Xray未在运行"
    fi
}

# 查看客户端信息
show_client_info() {
    if [ -f "$CONFIG_DIR/client_link.txt" ]; then
        print_color "green" "客户端连接信息:"
        cat "$CONFIG_DIR/client_link.txt"
        print_color "yellow" "提示: 请使用支持VLESS+Reality的客户端，如v2rayN, v2rayNG, Shadowrocket等"
    else
        print_color "red" "未找到客户端连接信息"
    fi
}

# 查看日志
view_logs() {
    print_color "blue" "最近的错误日志 (最后20行):"
    if [ -f "$LOG_DIR/error.log" ]; then
        tail -n 20 "$LOG_DIR/error.log"
    else
        print_color "yellow" "错误日志文件不存在"
    fi
    
    print_color "blue" "\n最近的访问日志 (最后20行):"
    if [ -f "$LOG_DIR/access.log" ]; then
        tail -n 20 "$LOG_DIR/access.log"
    else
        print_color "yellow" "访问日志文件不存在"
    fi
    
    print_color "blue" "\n运行日志 (最后20行):"
    if [ -f "$LOG_DIR/stdout.log" ]; then
        tail -n 20 "$LOG_DIR/stdout.log"
    else
        print_color "yellow" "运行日志文件不存在"
    fi
}

# 安全检查
security_check() {
    print_color "blue" "=== 安全状态检查 ==="
    
    # 检查端口状态
    local port=$(grep -o '"port": [0-9]*' "$CONFIG_DIR/config.json" | head -1 | awk '{print $2}')
    if netstat -an | grep -q ":$port "; then
        print_color "green" "端口 $port 正在监听"
    else
        print_color "yellow" "端口 $port 未在监听"
    fi
    
    # 检查配置文件权限
    if [ -f "$CONFIG_DIR/config.json" ]; then
        local perms=$(stat -f "%Mp%Lp" "$CONFIG_DIR/config.json")
        print_color "blue" "配置文件权限: $perms"
    fi
    
    # 检查日志文件大小
    for log_file in "$LOG_DIR/access.log" "$LOG_DIR/error.log" "$LOG_DIR/stdout.log"; do
        if [ -f "$log_file" ]; then
            local size=$(stat -f "%z" "$log_file")
            print_color "blue" "$(basename "$log_file"): ${size} bytes"
        fi
    done
    
    # 显示连接统计
    if [ -f "$LOG_DIR/access.log" ]; then
        local conn_count=$(grep -c "accepted" "$LOG_DIR/access.log" 2>/dev/null || echo "0")
        print_color "blue" "总连接数: $conn_count"
    fi
}

# 卸载Xray
uninstall_xray() {
    print_color "yellow" "警告: 此操作将完全删除Xray及其所有配置文件"
    printf "${RED}确定要卸载吗? (y/n): ${PLAIN}"
    read -r confirm
    if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
        stop_xray
        print_color "blue" "删除Xray文件..."
        rm -rf "$WORK_DIR"
        print_color "green" "Xray已完全卸载"
        exit 0
    else
        print_color "blue" "已取消卸载"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo "========================================"
    echo "    Xray FreeBSD 管理脚本 v1.0        "
    echo "========================================"
    echo ""
    
    if check_running; then
        echo -e "${GREEN}Xray状态: 运行中${PLAIN}"
    else
        echo -e "${RED}Xray状态: 未运行${PLAIN}"
    fi
    
    echo ""
    echo "  1. 启动 Xray"
    echo "  2. 停止 Xray"
    echo "  3. 重启 Xray"
    echo "  4. 查看 Xray 状态"
    echo "  5. 查看客户端连接信息"
    echo "  6. 查看日志"
    echo "  7. 安全状态检查"
    echo "  8. 卸载 Xray"
    echo "  0. 退出脚本"
    echo ""
    echo "========================================"
    printf "请选择操作 [0-8]: "
}

# 主循环
while true; do
    show_menu
    read -r choice
    case "$choice" in
        1) start_xray ;;  
        2) stop_xray ;;   
        3) restart_xray ;;
        4) status_xray ;; 
        5) show_client_info ;;
        6) view_logs ;;   
        7) security_check ;;
        8) uninstall_xray ;;
        0) exit 0 ;;      
        *) print_color "red" "无效的选择，请重试" ;;
    esac
    printf "\n按Enter键继续..."
    read -r dummy
done
EOF

    chmod +x "$WORK_DIR/menu.sh"
    print_color "green" "管理脚本已创建: $WORK_DIR/menu.sh"
}

# 主函数
main() {
    print_color "green" "===== FreeBSD Xray安装脚本 - 增强安全版本 ====="
    print_color "blue" "适用于FreeBSD 14.1 amd64架构"
    print_color "blue" "Xray版本: v25.5.16 (最新稳定版)"
    print_color "yellow" "注意: 此脚本将在用户目录下安装Xray，具备增强的安全特性"
    
    # 检查系统
    check_system
    
    # 检查依赖
    check_dependencies
    
    # 创建工作目录
    create_directories
    
    # 下载Xray
    download_xray
    
    # 配置Xray
    configure_xray
    
    # 创建管理脚本
    create_management_script
    
    print_color "green" "===== 安装完成 ====="
    print_color "blue" "Xray v25.5.16 已安装到: $WORK_DIR"
    print_color "blue" "配置文件位于: $CONFIG_DIR/config.json"
    print_color "blue" "管理脚本: $WORK_DIR/menu.sh"
    print_color "yellow" "使用方法: sh $WORK_DIR/menu.sh"
    print_color "green" "\n=== 安全特性 ==="
    print_color "blue" "✓ 多短ID配置增强安全性"
    print_color "blue" "✓ 随机伪装域名降低特征"
    print_color "blue" "✓ 智能端口选择和检测"
    print_color "blue" "✓ 增强的路由规则和广告拦截"
    print_color "blue" "✓ 多重IP检测机制"
    
    # 显示客户端信息
    print_color "green" "\n===== 客户端连接信息 ====="
    if [ -f "$CONFIG_DIR/client_link.txt" ]; then
        cat "$CONFIG_DIR/client_link.txt"
    fi
    print_color "yellow" "提示: 请使用支持VLESS+Reality的客户端，如v2rayN, v2rayNG, Shadowrocket等"
    
    # 询问是否立即启动
    printf "${BLUE}是否立即启动Xray? (y/n): ${PLAIN}"
    read -r start_now
    if [ "$start_now" = "y" ] || [ "$start_now" = "Y" ]; then
        sh "$WORK_DIR/menu.sh" 1
    else
        print_color "blue" "您可以稍后使用管理脚本启动Xray"
    fi
}

# 执行主函数
main
