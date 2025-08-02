#!/bin/sh
# FreeBSD Xray远程安装脚本 - 简化版
# 适用于通过SSH从Windows连接到FreeBSD系统

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

# 检查系统
check_system() {
    if [ "$(uname -s)" != "FreeBSD" ]; then
        print_color "red" "错误: 此脚本仅适用于FreeBSD系统"
        exit 1
    fi
    
    print_color "green" "系统检测通过: FreeBSD $(uname -r) $(uname -m)"
}

# 下载完整安装脚本
download_installer() {
    print_color "blue" "下载完整安装脚本..."
    
    # 创建临时目录
    TMP_DIR="/tmp/xray_installer"
    mkdir -p "$TMP_DIR"
    
    # 下载安装脚本
    if ! fetch -o "$TMP_DIR/freebsd_xray_installer.sh" "https://raw.githubusercontent.com/dayao888/v2ray-agent/master/freebsd_xray_installer.sh" 2>/dev/null; then
        print_color "yellow" "无法从GitHub下载，使用本地脚本..."
        
        # 如果下载失败，使用内联脚本
        cat > "$TMP_DIR/freebsd_xray_installer.sh" << 'EOFSCRIPT'
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

# 生成随机端口（10000-65535）
generate_port() {
    echo $((RANDOM % 55535 + 10000))
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
    
    # 生成短ID
    SHORT_ID=$(openssl rand -hex 8)
    print_color "green" "已生成Short ID: $SHORT_ID"
    
    # 选择一个流行的域名作为伪装
    FAKE_DOMAIN="www.microsoft.com"
    
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
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$FAKE_DOMAIN:443",
          "serverNames": [
            "$FAKE_DOMAIN"
          ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [
            "$SHORT_ID"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
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
      }
    ]
  }
}
EOF

    print_color "green" "Xray配置文件已生成: $CONFIG_DIR/config.json"
    
    # 保存连接信息
    SERVER_IP=$(curl -s https://api.ipify.org || curl -s https://ifconfig.me)
    if [ -z "$SERVER_IP" ]; then
        print_color "yellow" "警告: 无法获取服务器IP地址，请手动替换以下链接中的SERVER_IP部分"
        SERVER_IP="SERVER_IP"
    fi
    
    # 生成V2Ray链接
    VLESS_LINK="vless://$UUID@$SERVER_IP:$XRAY_PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$FAKE_DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#FreeBSD-VLESS-Reality"
    
    echo "$VLESS_LINK" > "$CONFIG_DIR/client_link.txt"
    print_color "green" "客户端连接信息已保存至: $CONFIG_DIR/client_link.txt"
}

# 创建管理脚本
create_management_script() {
    print_color "blue" "创建管理脚本..."
    
    # 使用修复后的菜单脚本
    cp "$(dirname "$0")/fixed_menu.sh" "$WORK_DIR/menu.sh"
    chmod +x "$WORK_DIR/menu.sh"
    print_color "green" "管理脚本已创建: $WORK_DIR/menu.sh"
    return
    
    # 以下是原始脚本，已被替换
    cat > "$WORK_DIR/menu.sh.bak" << 'EOF'
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
    
    # 验证配置文件...
    print_color "blue" "验证配置文件..."
    if ! python3 -m json.tool "$CONFIG_DIR/config.json" > "$LOG_DIR/config_test.log" 2>&1 && ! jq . "$CONFIG_DIR/config.json" > "$LOG_DIR/config_test.log" 2>&1; then
        print_color "red" "配置文件验证失败，请检查: $LOG_DIR/config_test.log"
        return 1
    fi
    
    print_color "blue" "启动Xray..."
    nohup "$BIN_DIR/xray" run -c "$CONFIG_DIR/config.json" > "$LOG_DIR/stdout.log" 2>&1 &
    echo $! > "$PID_FILE"
    
    sleep 2
    if check_running; then
        print_color "green" "Xray启动成功，PID: $(cat "$PID_FILE")"
    else
        print_color "red" "Xray启动失败，请检查日志: $LOG_DIR/stdout.log"
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
    echo "  7. 卸载 Xray"
    echo "  0. 退出脚本"
    echo ""
    echo "========================================"
    printf "请选择操作 [0-7]: "
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
        7) uninstall_xray ;;
        0) exit 0 ;;      
        *) print_color "red" "无效的选择，请重试" ;;
    esac
    printf "\n按Enter键继续..."
    read -r
done
EOF

    chmod +x "$WORK_DIR/menu.sh"
    print_color "green" "管理脚本已创建: $WORK_DIR/menu.sh"
}

# 主函数
main() {
    print_color "green" "===== FreeBSD Xray安装脚本 - 无需root权限版本 ====="
    print_color "blue" "适用于FreeBSD 14.1 amd64架构"
    print_color "yellow" "注意: 此脚本将在用户目录下安装Xray"
    
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
    print_color "blue" "Xray已安装到: $WORK_DIR"
    print_color "blue" "配置文件位于: $CONFIG_DIR/config.json"
    print_color "blue" "管理脚本: $WORK_DIR/menu.sh"
    print_color "yellow" "使用方法: sh $WORK_DIR/menu.sh"
    
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
EOFSCRIPT
    fi
    
    chmod +x "$TMP_DIR/freebsd_xray_installer.sh"
    print_color "green" "安装脚本准备就绪"
}

# 主函数
main() {
    print_color "green" "===== FreeBSD Xray远程安装助手 ====="
    print_color "blue" "此脚本将帮助您在FreeBSD系统上安装Xray"
    
    # 检查系统
    check_system
    
    # 下载安装脚本
    download_installer
    
    # 运行安装脚本
    print_color "blue" "开始安装Xray..."
    sh "$TMP_DIR/freebsd_xray_installer.sh"
    
    # 清理临时文件
    rm -rf "$TMP_DIR"
}

# 执行主函数
main
