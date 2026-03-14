#!/bin/bash
# shadowsocksR/SSR Ubuntu 一键安装脚本（最终修复版）
# 针对 Python 3.13 全面修复 collections 导入问题
# 仓库：https://github.com/xnjwithwd/SSER

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[36m"
PLAIN="\033[0m"

V6_PROXY=""
IP=$(curl -sL -4 ip.sb 2>/dev/null)
if [[ "$?" != "0" || -z "$IP" ]]; then
    IP=$(curl -sL -6 ip.sb 2>/dev/null)
    V6_PROXY=""
fi

FILENAME="ShadowsocksR-v3.2.2"
URL="${V6_PROXY}https://github.com/shadowsocksrr/shadowsocksr/archive/3.2.2.tar.gz"
BASE=$(pwd)

CONFIG_FILE="/etc/shadowsocksR.json"
SERVICE_FILE="/lib/systemd/system/shadowsocksR.service"
SSR_USER="ssr"
SSR_HOME="/usr/local/shadowsocks"

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    if [[ $EUID -ne 0 ]]; then
        colorEcho $RED "请以 root 身份执行该脚本"
        exit 1
    fi

    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        colorEcho $RED "无法识别系统版本"
        exit 1
    fi

    if [[ ! $OS =~ Ubuntu ]]; then
        colorEcho $RED "当前系统不是 Ubuntu"
        exit 1
    fi

    main_ver=${VER%%.*}
    if [[ $main_ver -lt 16 ]]; then
        colorEcho $RED "Ubuntu 版本必须 >= 16.04"
        exit 1
    fi
}

slogon() {
    clear
    echo "#############################################################"
    echo -e "#          ${RED}Ubuntu LTS ShadowsocksR/SSR 一键安装脚本${PLAIN}          #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""
}

get_password() {
    local pw
    while true; do
        read -p " 请设置 SSR 密码（不输入则随机生成）: " pw
        if [[ -z "$pw" ]]; then
            pw=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
            break
        elif [[ "$pw" =~ [^[:print:]] || "$pw" =~ [\"\'\\\ ] ]]; then
            colorEcho $RED " 密码不能包含引号、反斜杠或空格，请重新输入"
        else
            break
        fi
    done
    echo "$pw"
}

getData() {
    PASSWORD=$(get_password)
    echo ""
    colorEcho $BLUE " 密码： $PASSWORD"
    echo ""

    while true; do
        read -p " 请设置 SSR 端口号 [1-65535]（默认 12345）: " PORT
        [[ -z "$PORT" ]] && PORT="12345"
        if [[ ! "$PORT" =~ ^[0-9]+$ ]] || [[ $PORT -lt 1 || $PORT -gt 65535 ]]; then
            colorEcho $RED " 输入错误，端口号需为 1-65535 的数字"
            continue
        fi
        if ss -tuln | grep -q ":$PORT "; then
            colorEcho $RED " 端口 $PORT 已被占用，请选择其他端口"
        else
            break
        fi
    done
    echo ""
    colorEcho $BLUE " 端口号： $PORT"
    echo ""

    colorEcho $BLUE " 请选择 SSR 加密方式（推荐 aes-256-cfb）:"
    echo "   1) aes-256-cfb  2) aes-192-cfb  3) aes-128-cfb"
    echo "   4) aes-256-ctr  5) aes-192-ctr  6) aes-128-ctr"
    echo "   7) aes-256-cfb8 8) aes-192-cfb8 9) aes-128-cfb8"
    echo "   10) camellia-128-cfb  11) camellia-192-cfb  12) camellia-256-cfb"
    echo "   13) chacha20-ietf"
    read -p " 请选择 [1-13]（默认 1）: " answer
    case $answer in
        2) METHOD="aes-192-cfb" ;;
        3) METHOD="aes-128-cfb" ;;
        4) METHOD="aes-256-ctr" ;;
        5) METHOD="aes-192-ctr" ;;
        6) METHOD="aes-128-ctr" ;;
        7) METHOD="aes-256-cfb8" ;;
        8) METHOD="aes-192-cfb8" ;;
        9) METHOD="aes-128-cfb8" ;;
        10) METHOD="camellia-128-cfb" ;;
        11) METHOD="camellia-192-cfb" ;;
        12) METHOD="camellia-256-cfb" ;;
        13) METHOD="chacha20-ietf" ;;
        *) METHOD="aes-256-cfb" ;;
    esac
    echo ""
    colorEcho $BLUE " 加密方式： $METHOD"
    echo ""

    colorEcho $BLUE " 请选择 SSR 协议（推荐 auth_chain_a）:"
    echo "   1) origin           2) verify_deflate   3) auth_sha1_v4"
    echo "   4) auth_aes128_md5  5) auth_aes128_sha1 6) auth_chain_a"
    echo "   7) auth_chain_b     8) auth_chain_c     9) auth_chain_d"
    echo "   10) auth_chain_e    11) auth_chain_f"
    read -p " 请选择 [1-11]（默认 6）: " answer
    case $answer in
        1) PROTOCOL="origin" ;;
        2) PROTOCOL="verify_deflate" ;;
        3) PROTOCOL="auth_sha1_v4" ;;
        4) PROTOCOL="auth_aes128_md5" ;;
        5) PROTOCOL="auth_aes128_sha1" ;;
        7) PROTOCOL="auth_chain_b" ;;
        8) PROTOCOL="auth_chain_c" ;;
        9) PROTOCOL="auth_chain_d" ;;
        10) PROTOCOL="auth_chain_e" ;;
        11) PROTOCOL="auth_chain_f" ;;
        *) PROTOCOL="auth_chain_a" ;;
    esac
    echo ""
    colorEcho $BLUE " 协议： $PROTOCOL"
    echo ""

    colorEcho $BLUE " 请选择 SSR 混淆模式（推荐 tls1.2_ticket_auth）:"
    echo "   1) plain"
    echo "   2) http_simple"
    echo "   3) http_post"
    echo "   4) tls1.2_ticket_auth"
    echo "   5) tls1.2_ticket_fastauth"
    read -p " 请选择 [1-5]（默认 4）: " answer
    case $answer in
        1) OBFS="plain" ;;
        2) OBFS="http_simple" ;;
        3) OBFS="http_post" ;;
        5) OBFS="tls1.2_ticket_fastauth" ;;
        *) OBFS="tls1.2_ticket_auth" ;;
    esac
    echo ""
    colorEcho $BLUE " 混淆模式： $OBFS"
    echo ""
}

preinstall() {
    colorEcho $BLUE " 更新软件包列表并安装必要组件"
    apt update
    apt install -y curl wget vim net-tools libsodium23 openssl unzip qrencode python3

    if [[ ! -e /usr/bin/python ]]; then
        ln -s /usr/bin/python3 /usr/bin/python
    fi

    apt autoremove -y
}

installBBR() {
    if lsmod | grep -q bbr; then
        colorEcho $BLUE " BBR 已经启用"
        INSTALL_BBR=false
        return
    fi

    if ! command -v systemd-detect-virt &>/dev/null || [[ $(systemd-detect-virt) == "openvz" ]]; then
        colorEcho $YELLOW " 虚拟化环境可能不支持 BBR，跳过安装"
        INSTALL_BBR=false
        return
    fi

    kernel_ver=$(uname -r | cut -d. -f1-2)
    if [[ $(echo "$kernel_ver >= 4.9" | bc) -eq 1 ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
        if lsmod | grep -q bbr; then
            colorEcho $GREEN " BBR 已启用"
            INSTALL_BBR=false
            return
        fi
    fi

    colorEcho $BLUE " 正在安装支持 BBR 的内核（HWE）..."
    apt install -y --install-recommends linux-generic-hwe-$(lsb_release -r -s)
    grub-set-default 0
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
    INSTALL_BBR=true
}

installSSR() {
    if [[ -d $SSR_HOME ]]; then
        colorEcho $YELLOW " 检测到 SSR 已安装，跳过下载"
    else
        colorEcho $BLUE " 下载 ShadowsocksR"
        if ! wget --no-check-certificate -O ${FILENAME}.tar.gz $URL; then
            colorEcho $RED " 下载失败，请检查网络"
            exit 1
        fi

        tar -zxf ${FILENAME}.tar.gz
        mv shadowsocksr-3.2.2/shadowsocks $SSR_HOME
        rm -rf shadowsocksr-3.2.2 ${FILENAME}.tar.gz

        if [[ ! -f $SSR_HOME/server.py ]]; then
            colorEcho $RED " 安装失败，文件不完整"
            exit 1
        fi
    fi

    colorEcho $BLUE " 全面修复 Python 3.13 兼容性问题"

    # 修复1：lru_cache.py 中错误地从 collections.abc 导入 OrderedDict
    if [[ -f $SSR_HOME/lru_cache.py ]]; then
        sed -i 's/from collections\.abc import OrderedDict/from collections import OrderedDict/' $SSR_HOME/lru_cache.py
    fi

    # 修复2：ordereddict.py 中使用 collections.MutableMapping -> collections.abc.MutableMapping
    if [[ -f $SSR_HOME/ordereddict.py ]]; then
        sed -i 's/collections\.MutableMapping/collections.abc.MutableMapping/g' $SSR_HOME/ordereddict.py
    fi

    # 修复3：eventloop.py 中错误地从 collections.abc 导入 defaultdict
    if [[ -f $SSR_HOME/eventloop.py ]]; then
        sed -i 's/from collections\.abc import defaultdict/from collections import defaultdict/' $SSR_HOME/eventloop.py
    fi

    # 修复4：确保 server.py 使用 python3
    sed -i '1s/.*/#!\/usr\/bin\/env python3/' $SSR_HOME/server.py

    # 创建运行用户
    if ! id -u $SSR_USER >/dev/null 2>&1; then
        useradd -r -s /sbin/nologin $SSR_USER
    fi

    # 生成配置文件
    cat > $CONFIG_FILE <<EOF
{
    "server":"0.0.0.0",
    "server_ipv6":"::",
    "server_port":${PORT},
    "local_port":1080,
    "password":"${PASSWORD}",
    "timeout":600,
    "method":"${METHOD}",
    "protocol":"${PROTOCOL}",
    "protocol_param":"",
    "obfs":"${OBFS}",
    "obfs_param":"",
    "redirect":"",
    "dns_ipv6":false,
    "fast_open":false,
    "workers":1
}
EOF

    chown $SSR_USER:$SSR_USER $CONFIG_FILE
    chmod 600 $CONFIG_FILE

    # 创建 systemd 服务文件（使用 Type=simple）
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=ShadowsocksR Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=$SSR_USER
Group=$SSR_USER
LimitNOFILE=32768
ExecStart=$SSR_HOME/server.py -c $CONFIG_FILE start
ExecStop=/bin/kill -s TERM \$MAINPID
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable shadowsocksR
    systemctl restart shadowsocksR

    sleep 3
    if ! systemctl is-active shadowsocksR >/dev/null 2>&1; then
        colorEcho $RED " SSR 启动失败，正在收集错误信息..."
        journalctl -u shadowsocksR -n 20 --no-pager
        colorEcho $YELLOW "尝试手动运行以获取更多错误信息："
        sudo -u $SSR_USER $SSR_HOME/server.py -c $CONFIG_FILE start
        exit 1
    fi
    colorEcho $GREEN " SSR 启动成功"
}

setFirewall() {
    if command -v ufw >/dev/null 2>&1; then
        if ufw status | grep -q inactive; then
            colorEcho $YELLOW " 防火墙未启用，请手动开放端口 $PORT 或启用 ufw"
        else
            ufw allow ${PORT}/tcp
            ufw allow ${PORT}/udp
            colorEcho $GREEN " 防火墙端口 $PORT (TCP/UDP) 已开放"
        fi
    else
        colorEcho $YELLOW " 未检测到 ufw，请自行配置防火墙放行端口 $PORT"
    fi
}

info() {
    if [[ ! -f $CONFIG_FILE ]]; then
        colorEcho $RED " 配置文件不存在，请先安装 SSR"
        return
    fi

    local port=$(grep server_port $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    local password=$(grep password $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    local method=$(grep method $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    local protocol=$(grep protocol $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')
    local obfs=$(grep obfs $CONFIG_FILE | cut -d: -f2 | tr -d \",' ')

    local status
    if systemctl is-active shadowsocksR >/dev/null 2>&1; then
        status="${GREEN}正在运行${PLAIN}"
    else
        status="${RED}已停止${PLAIN}"
    fi

    local ip_addr=$IP
    if [[ -z "$ip_addr" ]]; then
        ip_addr=$(curl -sL -6 ip.sb 2>/dev/null)
    fi
    if [[ -z "$ip_addr" ]]; then
        ip_addr="无法获取公网 IP"
    fi

    echo "============================================"
    echo -e " ${BLUE}SSR 运行状态：${PLAIN}${status}"
    echo -e " ${BLUE}配置文件：${PLAIN}${RED}$CONFIG_FILE${PLAIN}"
    echo ""
    echo -e " ${RED}SSR 配置信息：${PLAIN}"
    echo -e "   ${BLUE}IP 地址: ${PLAIN} ${RED}${ip_addr}${PLAIN}"
    echo -e "   ${BLUE}端口: ${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}密码: ${PLAIN} ${RED}${password}${PLAIN}"
    echo -e "   ${BLUE}加密方式: ${PLAIN} ${RED}${method}${PLAIN}"
    echo -e "   ${BLUE}协议: ${PLAIN} ${RED}${protocol}${PLAIN}"
    echo -e "   ${BLUE}混淆: ${PLAIN} ${RED}${obfs}${PLAIN}"
    echo ""

    local p1=$(echo -n ${password} | base64 | tr -d '\n=' | tr '+/' '-_')
    local base="/?remarks=&protoparam=&obfsparam="
    local raw="${ip_addr}:${port}:${protocol}:${method}:${obfs}:${p1}${base}"
    local link="ssr://$(echo -n $raw | base64 | tr -d '\n=' | tr '+/' '-_')"

    echo -e " ${BLUE}SSR 链接:${PLAIN} $link"
    if command -v qrencode >/dev/null 2>&1; then
        qrencode -o - -t utf8 "$link" 2>/dev/null || echo "二维码生成失败（qrencode 输出问题）"
    else
        echo "请安装 qrencode 以显示二维码"
    fi
    echo "============================================"
}

uninstall() {
    read -p " 确定卸载 SSR 吗？(y/n) " answer
    [[ -z "$answer" || ! "$answer" =~ [yY] ]] && return

    systemctl stop shadowsocksR
    systemctl disable shadowsocksR
    rm -f $SERVICE_FILE
    rm -f $CONFIG_FILE
    rm -rf $SSR_HOME
    rm -f /var/log/shadowsocks.log

    if id -u $SSR_USER >/dev/null 2>&1; then
        userdel -r $SSR_USER 2>/dev/null
    fi

    colorEcho $GREEN " SSR 已卸载"
}

bbrReboot() {
    if [[ "$INSTALL_BBR" == "true" ]]; then
        echo ""
        colorEcho $BLUE " BBR 内核已安装，需要重启系统生效"
        read -p " 是否立即重启？(y/n) " answer
        if [[ "$answer" =~ [yY] ]]; then
            reboot
        else
            colorEcho $YELLOW " 请稍后手动重启系统"
        fi
    fi
}

install() {
    checkSystem
    slogon
    getData
    preinstall
    installBBR
    installSSR
    setFirewall
    info
    bbrReboot
}

show_help() {
    echo "用法: $0 [install|uninstall|info]"
    echo "  install   - 安装 ShadowsocksR"
    echo "  uninstall - 卸载 ShadowsocksR"
    echo "  info      - 查看配置信息"
    echo "  无参数时默认执行 install"
}

slogon
action=${1:-install}
case "$action" in
    install|uninstall|info)
        $action
        ;;
    *)
        show_help
        ;;
esac
