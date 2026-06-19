#!/bin/bash
# ================================================================
# Gost Proxy Manager v4.0
# 一键管理 HTTPS / HTTP / SOCKS5 代理，基于 Gost + Docker
# ================================================================
# 用法:

# ================================================================
# License: MIT
# ================================================================

# --- 颜色 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_title() { echo -e "${BLUE}===== $1 =====${NC}"; }

# ================================================================
# root 权限检查（非 root 直接退出）
# ================================================================
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[ERROR]${NC} 此脚本需要 root 权限才能运行！"
    exit 1
fi

# --- 服务定义 ---
SERVICE_HTTPS="https"
SERVICE_HTTP="http"
SERVICE_S5="s5"

# --- 密码净化 ---
sanitize_pass() {
    echo "$1" | tr -cd 'A-Za-z0-9'
}

# --- 获取公网IP ---
get_server_ip() {
    local ip
    ip=$(curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 ip.sb 2>/dev/null || curl -s -4 icanhazip.com 2>/dev/null)
    [ -z "$ip" ] && ip=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d/ -f1 | head -n1)
    [ -z "$ip" ] && ip="127.0.0.1"
    echo "$ip"
}

# --- 设置服务配置 ---
set_config() {
    local service="$1"
    case "$service" in
        https)
            CONTAINER_NAME="gost-https-proxy"
            CONFIG_DIR="/etc/proxy-manager-https"
            CERT_FILE="${CONFIG_DIR}/cert.pem"
            KEY_FILE="${CONFIG_DIR}/key.pem"
            CONFIG_FILE="${CONFIG_DIR}/config.env"
            DEFAULT_PORT="8443"
            DEFAULT_USER="admin"
            DEFAULT_PASS="123456"
            NEED_CERT=1
            PROTO="https"
            GOST_PROTO="https"
            ;;
        http)
            CONTAINER_NAME="gost-http-proxy"
            CONFIG_DIR="/etc/proxy-manager-http"
            CERT_FILE=""
            KEY_FILE=""
            CONFIG_FILE="${CONFIG_DIR}/config.env"
            DEFAULT_PORT="8080"
            DEFAULT_USER="admin"
            DEFAULT_PASS="123456"
            NEED_CERT=0
            PROTO="http"
            GOST_PROTO="http"
            ;;
        s5|socks5)
            CONTAINER_NAME="gost-socks5-proxy"
            CONFIG_DIR="/etc/proxy-manager-s5"
            CERT_FILE=""
            KEY_FILE=""
            CONFIG_FILE="${CONFIG_DIR}/config.env"
            DEFAULT_PORT="1080"
            DEFAULT_USER="admin"
            DEFAULT_PASS="123456"
            NEED_CERT=0
            PROTO="socks5"
            GOST_PROTO="socks5"
            ;;
        *)
            print_error "未知服务: $service (支持: https, http, s5)"
            return 1
            ;;
    esac
    return 0
}

# --- 加载配置 ---
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
        return 0
    else
        return 1
    fi
}

# --- 保存配置 ---
save_config() {
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" <<EOF
PORT="$PORT"
USER="$USER"
PASS="$PASS"
SERVER_IP="$SERVER_IP"
EOF
}

# --- 检查 Docker ---
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装，请先安装 Docker"
        exit 1
    fi
}

# --- 生成证书（仅 HTTPS） ---
generate_cert() {
    if [ "$NEED_CERT" -eq 0 ]; then
        return 0
    fi
    mkdir -p "$CONFIG_DIR"
    local ip="$1"
    print_info "生成 10 年有效期证书 (绑定 IP: $ip) ..."
    openssl req -x509 -newkey rsa:4096 -nodes \
        -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -days 3650 \
        -subj "/C=CN/ST=GD/L=SZ/O=Proxy/CN=Proxy-CA" \
        -addext "subjectAltName=IP:$ip,DNS:localhost,DNS:*.local" 2>/dev/null
    if [ $? -eq 0 ] && [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ]; then
        print_info "证书生成成功: $CERT_FILE"
        return 0
    else
        print_error "证书生成失败，请检查 openssl 是否安装"
        exit 1
    fi
}

# --- 安装/更新 ---
do_install() {
    local service="$1"
    shift
    set_config "$service" || return 1
    check_docker

    if [ -z "$1" ]; then
        read -p "请输入监听端口 [默认: $DEFAULT_PORT]: " input_port
        PORT="${input_port:-$DEFAULT_PORT}"
        read -p "请输入用户名 [默认: $DEFAULT_USER]: " input_user
        USER="${input_user:-$DEFAULT_USER}"
        read -p "请输入密码 [默认: $DEFAULT_PASS]: " raw_pass
        raw_pass="${raw_pass:-$DEFAULT_PASS}"
        PASS=$(sanitize_pass "$raw_pass")
        [ "$PASS" != "$raw_pass" ] && print_warn "密码已净化: $PASS"
    else
        PORT="${1:-$DEFAULT_PORT}"
        USER="${2:-$DEFAULT_USER}"
        raw_pass="${3:-$DEFAULT_PASS}"
        PASS=$(sanitize_pass "$raw_pass")
    fi

    SERVER_IP=$(get_server_ip)
    print_info "服务器 IP: $SERVER_IP"

    # 处理证书
    if [ "$NEED_CERT" -eq 1 ]; then
        if [ -f "$CERT_FILE" ] && [ -f "$KEY_FILE" ] && [ -f "$CONFIG_FILE" ]; then
            load_config
            old_ip=$(grep SERVER_IP "$CONFIG_FILE" | cut -d= -f2)
            old_port=$(grep PORT "$CONFIG_FILE" | cut -d= -f2)
            if [ "$SERVER_IP" != "$old_ip" ] || [ "$PORT" != "$old_port" ]; then
                print_warn "IP 或端口变化，重新生成证书..."
                generate_cert "$SERVER_IP"
            else
                print_info "证书已存在，跳过生成"
            fi
        else
            generate_cert "$SERVER_IP"
        fi
    fi

    save_config

    docker stop "$CONTAINER_NAME" &>/dev/null
    docker rm "$CONTAINER_NAME" &>/dev/null

    print_info "正在启动 ${service} 代理容器 (端口: $PORT) ..."
    local cmd="docker run -d --restart=always --name $CONTAINER_NAME -p ${PORT}:${PORT}"
    if [ "$NEED_CERT" -eq 1 ]; then
        cmd="$cmd -v $CERT_FILE:/certs/cert.pem -v $KEY_FILE:/certs/key.pem"
        local url="${GOST_PROTO}://${USER}:${PASS}@:${PORT}?cert=/certs/cert.pem&key=/certs/key.pem"
    else
        local url="${GOST_PROTO}://${USER}:${PASS}@:${PORT}"
    fi
    cmd="$cmd ginuerzh/gost -L \"$url\""
    eval $cmd

    if [ $? -eq 0 ]; then
        print_title "${service} 代理部署成功"
        echo -e "🔗 代理地址: ${GREEN}${PROTO}://${USER}:${PASS}@${SERVER_IP}:${PORT}${NC}"
        [ "$NEED_CERT" -eq 1 ] && echo -e "⚠️  浏览器访问会提示不安全，点击「高级」->「继续前往」即可"
        [ "$NEED_CERT" -eq 1 ] && echo -e "📅 证书有效期: 10 年"
        echo -e "📂 配置文件目录: $CONFIG_DIR"
        echo -e "💡 管理命令: proxy-manager $service [status|stop|start|restart|change|uninstall]"
    else
        print_error "容器启动失败，请检查 Docker 日志"
        exit 1
    fi
}

# --- 状态查看 ---
do_status() {
    local service="$1"
    set_config "$service" || return 1
    print_title "${service} 代理状态"
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_warn "容器未安装或已被删除"
        return
    fi

    local running=$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)
    local status="停止"
    local color=$RED
    [ "$running" == "true" ] && status="运行中" && color=$GREEN
    echo -e "容器状态: ${color}${status}${NC}"

    local port_map=$(docker port "$CONTAINER_NAME" ${PORT} 2>/dev/null | head -n1 | cut -d: -f2)
    [ -n "$port_map" ] && echo -e "映射端口: ${BLUE}$port_map${NC}" || { load_config && echo -e "配置端口: ${BLUE}$PORT${NC}"; }

    if [ "$NEED_CERT" -eq 1 ] && [ -f "$CERT_FILE" ]; then
        local expire=$(openssl x509 -enddate -noout -in "$CERT_FILE" 2>/dev/null | cut -d= -f2)
        echo -e "证书过期: ${BLUE}$expire${NC}"
    fi

    if load_config; then
        echo -e "用户名: ${BLUE}$USER${NC}"
        echo -e "密码:   ${BLUE}******${NC}"
        echo -e "配置目录: $CONFIG_DIR"
    fi

    echo -e "\n最近 5 行日志:"
    docker logs --tail 5 "$CONTAINER_NAME" 2>&1 | sed 's/^/  /'
}

# --- 启动 ---
do_start() {
    local service="$1"
    set_config "$service" || return 1
    print_info "启动容器 $CONTAINER_NAME ..."
    docker start "$CONTAINER_NAME" 2>/dev/null && print_info "已启动" || print_warn "启动失败"
}

# --- 停止 ---
do_stop() {
    local service="$1"
    set_config "$service" || return 1
    print_info "停止容器 $CONTAINER_NAME ..."
    docker stop "$CONTAINER_NAME" 2>/dev/null && print_info "已停止" || print_warn "容器未运行"
}

# --- 重启 ---
do_restart() {
    local service="$1"
    set_config "$service" || return 1
    print_info "重启容器 $CONTAINER_NAME ..."
    docker restart "$CONTAINER_NAME" 2>/dev/null && print_info "已重启" || print_warn "重启失败"
}

# --- 修改配置 ---
do_change() {
    local service="$1"
    set_config "$service" || return 1
    if ! load_config; then
        print_error "未找到现有配置，请先执行 install"
        return
    fi
    print_info "当前配置: 端口=$PORT, 用户=$USER"
    read -p "请输入新端口 (直接回车保持不变): " new_port
    read -p "请输入新用户名 (直接回车保持不变): " new_user
    read -p "请输入新密码 (直接回车保持不变): " raw_new_pass

    local changed=0
    [ -n "$new_port" ] && PORT="$new_port" && changed=1
    [ -n "$new_user" ] && USER="$new_user" && changed=1
    if [ -n "$raw_new_pass" ]; then
        PASS=$(sanitize_pass "$raw_new_pass")
        [ "$PASS" != "$raw_new_pass" ] && print_warn "密码已净化: $PASS"
        changed=1
    fi

    [ $changed -eq 0 ] && { print_warn "未做任何修改"; return; }
    print_info "应用新配置..."
    do_install "$service" "$PORT" "$USER" "$PASS"
}

# --- 卸载单个 ---
do_uninstall() {
    local service="$1"
    set_config "$service" || return 1
    print_warn "即将卸载 ${service} 代理 (删除容器、证书及配置文件)"
    read -p "确认删除所有数据？(输入 yes 确认): " confirm
    [ "$confirm" != "yes" ] && { print_info "已取消"; return; }

    docker stop "$CONTAINER_NAME" &>/dev/null
    docker rm "$CONTAINER_NAME" &>/dev/null
    print_info "容器已删除"
    [ -d "$CONFIG_DIR" ] && rm -rf "$CONFIG_DIR" && print_info "配置文件已删除 ($CONFIG_DIR)"
    print_info "${service} 代理卸载完成"
}

# --- 一键卸载所有 ---
uninstall_all() {
    print_warn "即将卸载 HTTPS、HTTP、SOCKS5 三个代理（容器 + 配置全部删除）"
    read -p "确认删除所有数据？(输入 yes 确认): " confirm
    [ "$confirm" != "yes" ] && { print_info "已取消"; return; }

    for svc in https http s5; do
        set_config "$svc"
        docker stop "$CONTAINER_NAME" &>/dev/null
        docker rm "$CONTAINER_NAME" &>/dev/null
        if [ -d "$CONFIG_DIR" ]; then
            rm -rf "$CONFIG_DIR"
            print_info "已删除 $CONFIG_DIR"
        fi
    done
    print_info "所有代理已完全卸载，文件已彻底清除"
}

# --- 子菜单 ---
manage_service() {
    local service="$1"
    local name=${service^^}
    if [ "$service" == "s5" ]; then
        name="SOCKS5"
    fi
    while true; do
        clear
        print_title "${name} 代理管理"
        echo " 1) 安装 / 重新安装"
        echo " 2) 查看状态"
        echo " 3) 启动代理"
        echo " 4) 停止代理"
        echo " 5) 重启代理"
        echo " 6) 修改端口/密码"
        echo " 7) 卸载 (删除所有)"
        echo " 0) 返回主菜单"
        echo "========================="
        read -p "请输入选项 [0-7]: " opt
        case $opt in
            1) do_install "$service" ;;
            2) do_status "$service"; read -p "按回车继续..." ;;
            3) do_start "$service"; read -p "按回车继续..." ;;
            4) do_stop "$service"; read -p "按回车继续..." ;;
            5) do_restart "$service"; read -p "按回车继续..." ;;
            6) do_change "$service"; read -p "按回车继续..." ;;
            7) do_uninstall "$service"; read -p "按回车继续..." ;;
            0) break ;;
            *) print_error "无效选项"; sleep 1 ;;
        esac
    done
}

# --- 主菜单 ---
main_menu() {
    while true; do
        clear
        print_title "Gost 三代理管理面板"
        # 显示状态
        for svc in https http s5; do
            set_config "$svc"
            if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
                local running=$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)
                [ "$running" == "true" ] && status="${GREEN}运行中${NC}" || status="${RED}已停止${NC}"
            else
                status="${YELLOW}未安装${NC}"
            fi
            if [ "$svc" == "s5" ]; then
                display_name="SOCKS5"
            else
                display_name="${svc^^}"
            fi
            echo -e " ${display_name} 代理: $status"
        done
        echo "========================="
        echo " 1) 管理 HTTPS 代理"
        echo " 2) 管理 HTTP 代理"
        echo " 3) 管理 SOCKS5 代理"
        echo " 8) 卸载所有（彻底删除全部文件）"
        echo " 0) 退出"
        echo "========================="
        read -p "请选择 [0-3,8]: " opt
        case $opt in
            1) manage_service "https" ;;
            2) manage_service "http" ;;
            3) manage_service "s5" ;;
            8) uninstall_all; read -p "按回车继续..." ;;
            0) exit 0 ;;
            *) print_error "无效选项"; sleep 1 ;;
        esac
    done
}

# --- 命令行入口 ---
if [ $# -eq 0 ]; then
    main_menu
else
    service="$1"
    action="$2"
    shift 2
    case "$service" in
        https|http|s5)
            case "$action" in
                install)   do_install "$service" "$@" ;;
                status)    do_status "$service" ;;
                start)     do_start "$service" ;;
                stop)      do_stop "$service" ;;
                restart)   do_restart "$service" ;;
                change)    do_change "$service" ;;
                uninstall) do_uninstall "$service" ;;
                *)         print_error "未知操作: $action"; exit 1 ;;
            esac
            ;;
        *)
            print_error "未知服务: $service (支持: https, http, s5)"
            exit 1
            ;;
    esac
fi
