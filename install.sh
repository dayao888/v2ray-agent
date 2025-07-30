cat > ~/install.sh << 'EOF'
#!/usr/bin/env bash
set -e
WORKDIR="$HOME/sing-box-no-root"
mkdir -p "$WORKDIR/bin" "$WORKDIR/config" "$WORKDIR/logs"
# 下载最新 sing-box
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then PLATFORM="linux-amd64"
elif [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then PLATFORM="linux-arm64"
else echo "Unsupported arch: $ARCH"; exit 1; fi
VERSION=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | head -n1 | cut -d '"' -f4)
curl -L "https://github.com/SagerNet/sing-box/releases/download/${VERSION}/sing-box-${VERSION}-${PLATFORM}.tar.gz" \
  | tar -xz -C "$WORKDIR/bin" --strip-components=1

# 生成配置 templates
cat > "$WORKDIR/config/vless.json" << EOF2
{
  "log": {"level":"info"},
  "inbounds":[{"type":"vless","listen":"0.0.0.0","listen_port":30001,
    "users":[{"uuid":"$(cat /proc/sys/kernel/random/uuid)","flow":"xtls-rprx-vision"}],
    "tls":{"enabled":true,"server_name":"www.cloudflare.com","reality":{"enabled":true,"handshake":{"server":"www.cloudflare.com","server_port":443},"private_key":"$(openssl ecparam -name prime256v1 -genkey -noout | openssl ec -outform DER | base64)","short_id":["$(openssl rand -hex 8)"]}}}],
  "outbounds":[{"type":"direct"}]
}
EOF2

cat > "$WORKDIR/config/hysteria2.json" << EOF2
{
  "log":{"level":"info"},
  "inbounds":[{"type":"hysteria2","listen":"0.0.0.0","listen_port":30002,"users":[{"password":"mypass123"}],
    "tls":{"enabled":true,"cert":"$WORKDIR/config/self.crt","key":"$WORKDIR/config/self.key"}}],
  "outbounds":[{"type":"direct"}]
}
EOF2

openssl req -x509 -newkey rsa:2048 -keyout "$WORKDIR/config/self.key" -out "$WORKDIR/config/self.crt" -days 365 -nodes -subj "/CN=localhost"

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
  echo "VLESS started (port 30001), pid $(cat $pidfile1)"
}
function start_hysteria(){
  nohup "$BIN" run -c "$WORKDIR/config/hysteria2.json" > "$LOG2" 2>&1 &
  echo $! > "$pidfile2"
  echo "Hysteria2 started (port 30002), pid $(cat $pidfile2)"
}
function stop_all(){
  kill $(cat $pidfile1 $pidfile2) 2>/dev/null || echo "Some services already stopped."
}
function show_menu(){
  clear
  echo "=== Sing‑box 管理面板 ==="
  echo "1) 启动 VLESS Reality Vision"
  echo "2) 启动 Hysteria2 TLS"
  echo "3) 停止所有服务"
  echo "4) 查看日志"
  echo "5) 查看配置"
  echo "6) 退出"
  echo -n "选择 [1-6]: "
}
while true; do
  show_menu
  read -r choice
  case $choice in
    1) start_vless;; 2) start_hysteria;; 3) stop_all;;
    4) echo "-- VLESS log --"; tail -n20 "$LOG1"; echo; echo "-- Hysteria2 log --"; tail -n20 "$LOG2";;
    5) echo "-- VLESS config --"; sed -n '1,20p' "$WORKDIR/config/vless.json"; echo; echo "-- Hysteria2 config --"; sed -n '1,20p' "$WORKDIR/config/hysteria2.json";;
    6) exit 0;;
    *) echo "无效选项";;
  esac
  echo "按回车继续…"; read
done
EOF2

chmod +x ~/install.sh ~/sing-box-no-root/menu.sh 2>/dev/null || true
echo "安装脚本已创建。下一步运行： bash ~/install.sh"
EOF
chmod +x ~/install.sh
