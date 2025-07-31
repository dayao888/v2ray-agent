check_port() {
    local port=$1
    # 优先使用 lsof，兼容性更好
    if command -v lsof >/dev/null 2>&1; then
        # 检查 TCP
        if lsof -iTCP:$port -sTCP:LISTEN >/dev/null 2>&1; then
            return 1 # 端口被占用
        fi
        # 检查 UDP
        if lsof -iUDP:$port >/dev/null 2>&1; then
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
