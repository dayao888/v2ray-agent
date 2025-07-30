cat > ~/install.sh << 'EOF'
#!/usr/bin/env bash
set -e

# 🚮 删除旧目录
echo "🧹 清理旧目录..."
rm -rf "$HOME/sing-box-no-root"

# 📁 初始化目录
WORKDIR="$HOME/sing-box-no-root"
mkdir -p "$WORKDIR/bin" "$WORKDIR/config" "$WORKDIR/logs"

# 🔍 判断架构
arch=$(uname -m)
if [[ "$arch" == "x86_64" || "$arch" == "amd64" ]]; then
    platform="amd64"
elif [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then
    platform="arm64"
else
    echo "❌ 不支持的架构: $arch"
    exit 1
fi

# 📥 下载并解压固定版本
version="1.11.9"
echo "📦 下载版本: $version"
url="https://github.com/SagerNet/sing-box/releases/download/v$version/sing-box-$version-linux-$platform.tar.gz"
wget -O sing-box.tar.gz "$url"
tar -zxf sing-box.tar.gz
mv "sing-box-$version-linux-$platform" "$WORKDIR/bin"
rm -f sing-box.tar.gz

# 🔑 生成密钥
UUID=$(cat /proc/sys/kernel/random/uuid)
KEYS=$("$WORKDIR/bin/sing-box" generate reality-key)
PRIVATE_KEY=$(echo "$KEYS" | grep PrivateKey | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep PublicKey | awk '{print $2}')
SHORT_ID=$(openssl rand -hex 8)
DOMAIN="www.5215211.xyz"
PORT=22724

# 📄 VLESS Reality 配置
cat > "$WORKDIR/config/vless.json" <<EOF2
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
EOF2

# 📄 Hysteria2 配置
cat > "$WORKDIR/config/hysteria2.json" <<EOF2
{
  "log": { "level": "info" },
  "inbounds": [{
    "type": "hysteria2",
    "listen": "0.0.0.0",
    "listen_port": 30002,
    "users": [{ "password": "mypass123" }],
    "tls": {
      "enabled": true,
      "cert": "$WORKDIR/config/self.crt",
      "key": "$WORKDIR/config/self.key"
    }
  }],
  "outbounds": [{ "type": "direct" }]
}
EOF2

# 📜 生成 TLS 证书
openssl req -x509 -newkey rsa:2048 -keyout "$WORKDIR/config/self.key" -out "$WORKDIR/config/self.crt" -days 365 -nodes -subj "/CN=localhost"

# 📋 管理面板脚本 menu.sh
cat > "$WORKDIR/menu.sh" << 'EOF2'
#!/usr/bin/env bash
WORKDIR="$HOME/sing-box-no-root"
BIN="$WORKDIR/bin/sing-box"
LOG1="$WORKDIR/logs/vless.log"
LOG2="$WORKDIR/logs/hysteria2.log"
pidfile1="$WORKDIR/logs/vless.pid"
pidfile2="$WORKDIR/logs/hysteria2.pid"

function start_vless(){
  nohup "$BIN" run -c "$WORKDIR/config/vless.json" > "$LOG1" 2>&1 &
  echo $! > "$pidfile1"
  echo "✅ VLESS 启动成功，端口: 22724，PID: $(cat $pidfile1)"
}
function start_hysteria(){
  nohup "$BIN" run -c "$WORKDIR/config/hysteria2.json" > "$LOG2" 2>&1 &
  echo $! > "$pidfile2"
  echo "✅ Hysteria2 启动成功，端口: 30002，PID: $(cat $pidfile2)"
}
function stop_all(){
  kill $(cat $pidfile1 $pidfile2 2>/dev/null) 2>/dev/null || echo "部分服务已关闭"
}
function show_menu(){
  clear
  echo "=== Sing-box 管理面板 ==="
  echo "1) 启动 VLESS Reality"
  echo "2) 启动 Hysteria2 TLS"
  echo "3) 停止全部服务"
  echo "4) 查看日志"
  echo "5) 查看配置"
  echo "6) 退出"
  echo -n "请选择 [1-6]: "
}
while true; do
  show_menu
  read -r choice
  case $choice in
    1) start_vless;; 2) start_hysteria;; 3) stop_all;;
    4) echo "-- VLESS log --"; tail -n20 "$LOG1"; echo; echo "-- Hysteria2 log --"; tail -n20 "$LOG2";;
    5) echo "-- VLESS config --"; head -n20 "$WORKDIR/config/vless.json"; echo; echo "-- Hysteria2 config --"; head -n20 "$WORKDIR/config/hysteria2.json";;
    6) exit 0;;
    *) echo "无效输入";;
  esac
  echo "按回车继续…"; read
done
EOF2

chmod +x "$WORKDIR/menu.sh"

# 🔗 输出客户端连接
echo
echo "✅ 安装完成，管理面板启动： bash ~/sing-box-no-root/menu.sh"
echo
echo "📎 v2rayN 客户端链接："
echo
echo "vless://$UUID@$DOMAIN:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$DOMAIN&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#vless_reality"
echo
EOF

# 执行安装
chmod +x ~/install.sh
bash ~/install.sh
