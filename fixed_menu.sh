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
    
    # 检查配置文件语法
    print_color "blue" "检查配置文件语法..."
    if ! python3 -m json.tool "$CONFIG_DIR/config.json" > "$LOG_DIR/config_test.log" 2>&1 && ! jq . "$CONFIG_DIR/config.json" > "$LOG_DIR/config_test.log" 2>&1; then
        print_color "red" "配置文件JSON格式错误，请检查: $LOG_DIR/config_test.log"
        return 1
    fi
    print_color "green" "配置文件格式检查通过"
    
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

# 安全状态检查
security_check() {
    print_color "blue" "执行安全状态检查..."
    
    # 检查Xray版本
    print_color "blue" "Xray版本信息:"
    "$BIN_DIR/xray" version
    
    # 检查配置文件权限
    print_color "blue" "\n配置文件权限:"
    ls -l "$CONFIG_DIR/config.json"
    
    # 检查端口占用
    PORT=$(grep -o '"port": [0-9]*' "$CONFIG_DIR/config.json" | awk '{print $2}')
    print_color "blue" "\n端口 $PORT 占用情况:"
    netstat -tuln | grep "$PORT" || print_color "yellow" "端口未被占用或netstat命令不可用"
    
    print_color "green" "\n安全检查完成"
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
    read -r
done
