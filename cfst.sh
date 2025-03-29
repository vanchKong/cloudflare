#!/bin/bash

# Cloudflare IP 优选管理脚本 (无标记版)
# 更新：支持批量添加/删除域名（空格/逗号分隔）
# 使用方法：保持与之前一致，参数可传入多个域名

# 配置参数
CF_DIR="/opt/CloudflareST"
CF_BIN="${CF_DIR}/CloudflareST"
INITIAL_DOMAINS=("ubits.club" "t.ubits.club" "zmpt.cc")  # 初始域名组

# 架构检测
setup_arch() {
    case $(uname -m) in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        arm64) echo "arm64" ;;
        *)       echo "unsupported" ;;
    esac
}

# 初始化环境
init_setup() {
    echo "作者：端端🐱/Gotchaaa，玩得开心～"
    echo "使用姿势请查阅：https://github.com/vanchKong/cloudflare"
    [ ! -d "$CF_DIR" ] && mkdir -p "$CF_DIR"
    
    # 首次运行时初始化 hosts 记录
    current_ip=$(get_current_ip)
    for domain in "${INITIAL_DOMAINS[@]}"; do
        if ! grep -q " ${domain}$" /etc/hosts; then
            [ -z "$current_ip" ] && current_ip="1.1.1.1"
            echo "${current_ip} ${domain}" >> /etc/hosts
        fi
    done
    echo "✅ 已初始化 hosts 文件"

    # 下载 CloudflareST
    if [ ! -f "$CF_BIN" ]; then
        arch=$(setup_arch)
        [ "$arch" = "unsupported" ] && echo "不支持的架构" && exit 1
        
        filename="CloudflareST_linux_${arch}.tar.gz"
        mirrors=(
            "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://ghproxy.com/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://ghfast.top/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://ghproxy.net/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://gh-proxy.com/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
        )

        for url in "${mirrors[@]}"; do
            if wget --show-progress --timeout=20 -O "${CF_DIR}/$filename" "$url"; then
                tar -zxf "${CF_DIR}/$filename" -C "$CF_DIR" && chmod +x "$CF_BIN"
                rm "${CF_DIR}/$filename"
                return 0
            fi
        done
        echo "下载失败" && exit 1
    fi
}

# 域名有效性检测
validate_domain() {
    local domain=$1
    echo "验证域名: $domain ..."
    
    local headers=$(curl -sIL "https://$domain" --connect-timeout 10 | grep -i 'server:')
    if [[ "$headers" =~ [Cc]loudflare ]]; then
        echo "✅ 有效 (托管于 Cloudflare)"
        return 0
    else
        echo "❌ 无效响应头: ${headers:-无数据}"
        return 1
    fi
}

# 添加单个域名
add_single_domain() {
    local domain=$1
    # 检测格式并去重
    if grep -q " ${domain}$" /etc/hosts; then
        echo "⚠️ 域名已存在: $domain" 
        return
    fi
    
    if validate_domain "$domain"; then
        # 更新hosts
        current_ip=$(get_current_ip)
        [ -z "$current_ip" ] && current_ip="1.1.1.1"
        echo "$current_ip $domain" >> /etc/hosts
        echo "✅ 已添加域名: $domain"
    else
        echo "❌ 跳过无效域名: $domain" 
    fi
}

# 删除单个域名
del_single_domain() {
    local domain=$1
    # 从hosts中删除
    if grep -q " ${domain}$" /etc/hosts; then
        sed -i "/ ${domain}$/d" /etc/hosts
        echo "✅ 已移除域名: $domain"
    else
        echo "⚠️ 域名不存在: $domain"
    fi
}

# 获取当前优选IP
get_current_ip() {
    if [ -f "${CF_DIR}/result.csv" ]; then
        awk -F ',' 'NR==2 {print $1}' "${CF_DIR}/result.csv"
    else
        grep " ${INITIAL_DOMAINS[0]}" /etc/hosts | awk '{print $1}'
    fi
}

# 执行优选并更新所有域名
run_update() {
    echo "⏳ 开始优选测试..."
    cd "$CF_DIR" && ./CloudflareST -dn 8 -tl 400 -sl 1
    
    local best_ip=$(get_current_ip)
    [ -z "$best_ip" ] && echo "❌ 优选失败" && exit 1
    
    echo "🔄 正在更新 hosts 文件..."
    # 遍历初始域名组更新IP
    for domain in "${INITIAL_DOMAINS[@]}"; do
        if grep -q " ${domain}$" /etc/hosts; then
            # 删除旧记录
            sed -i "/ ${domain}$/d" /etc/hosts
            # 添加新记录
            echo "$best_ip $domain" >> /etc/hosts
        fi
    done
    
    echo "✅ 所有域名已更新到最新IP: $best_ip"
}

# 查看托管列表
list_domains() {
    echo "当前托管的域名列表："
    for domain in "${INITIAL_DOMAINS[@]}"; do
        if grep -q " ${domain}$" /etc/hosts; then
            echo "$domain"
        fi
    done
}

# 主流程
main() {
    [ "$(id -u)" -ne 0 ] && echo "需要root权限" && exit 1
    init_setup

    case $1 in
        "-add")
            shift
            [ $# -eq 0 ] && echo "需要域名参数" && exit 1
            domains=$(echo "$@" | tr ',' ' ')
            for domain in $domains; do
                add_single_domain "$domain"
            done
            ;;
        "-del")
            shift
            [ $# -eq 0 ] && echo "需要域名参数" && exit 1
            domains=$(echo "$@" | tr ',' ' ')
            for domain in $domains; do
                del_single_domain "$domain"
            done
            ;;
        "-list")
            list_domains
            ;;
        *)
            run_update
            ;;
    esac
}

main "$@"
