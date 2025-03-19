#!/bin/bash

# Cloudflare IP 优选管理脚本 (无标记版)
# 更新：通过配置文件管理域名，hosts文件不再使用标记行
# 使用方法保持不变

# 配置参数
CF_DIR="/opt/CloudflareST"
CF_BIN="${CF_DIR}/CloudflareST"
CONFIG_FILE="${CF_DIR}/cfst_domains.conf"
INITIAL_DOMAINS=("ubits.club", "t.ubits.club" "zmpt.cc")  # 初始域名组

# 架构检测
setup_arch() {
    case $(uname -m) in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)       echo "unsupported" ;;
    esac
}

# 初始化环境
init_setup() {
    echo "作者：端端🐱/Gotchaaa，玩得开心～"
    [ ! -d "$CF_DIR" ] && mkdir -p "$CF_DIR"
    
    # 首次创建配置文件时初始化 hosts
    if [ ! -f "$CONFIG_FILE" ]; then
        printf "%s\n" "${INITIAL_DOMAINS[@]}" > "$CONFIG_FILE"
        echo "✅ 已创建初始配置文件"
        
        # 写入初始 hosts 记录（仅首次）
        current_ip="1.1.1.1"
        while read -r domain_group; do
            if ! grep -q "^${current_ip} ${domain_group}$" /etc/hosts; then
                echo "${current_ip} ${domain_group}" >> /etc/hosts
            fi
        done < "$CONFIG_FILE"
        echo "✅ 已初始化 hosts 文件"
    fi

    # 下载 CloudflareST
    if [ ! -f "$CF_BIN" ]; then
        arch=$(setup_arch)
        [ "$arch" = "unsupported" ] && echo "不支持的架构" && exit 1
        
        filename="CloudflareST_linux_${arch}.tar.gz"
        mirrors=(
            "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://ghproxy.com/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
        )

        for url in "${mirrors[@]}"; do
            if wget -q --timeout=20 -O "${CF_DIR}/$filename" "$url"; then
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

# 添加域名管理
add_domain() {
    local domain=$1
    # 检测格式并去重
    if grep -q "^${domain}$" "$CONFIG_FILE"; then
        echo "⚠️ 域名已存在" 
        return
    fi
    
    if validate_domain "$domain"; then
        # 写入配置文件
        echo "$domain" >> "$CONFIG_FILE"
        # 更新hosts
        current_ip=$(get_current_ip)
        [ -z "$current_ip" ] && current_ip="1.1.1.1"
        echo "$current_ip $domain" >> /etc/hosts
        echo "✅ 已添加域名: $domain"
    else
        echo "添加中止" 
        exit 1
    fi
}

# 删除域名
del_domain() {
    local domain=$1
    # 从配置文件中删除
    sed -i "/^${domain}$/d" "$CONFIG_FILE"
    # 从hosts中删除
    sed -i "/ ${domain}$/d" /etc/hosts
    echo "✅ 已移除域名: $domain"
}

# 获取当前优选IP
get_current_ip() {
    if [ -f "${CF_DIR}/result.csv" ]; then
        awk -F ',' 'NR==2 {print $1}' "${CF_DIR}/result.csv"
    else
        grep " ${INITIAL_DOMAINS[0]%% *}" /etc/hosts | awk '{print $1}'
    fi
}

# 执行优选并更新所有域名
run_update() {
    echo "⏳ 开始优选测试..."
    cd "$CF_DIR" && ./CloudflareST -dn 15 -tl 200 -sl 5
    
    local best_ip=$(get_current_ip)
    [ -z "$best_ip" ] && echo "❌ 优选失败" && exit 1
    
    echo "🔄 正在更新 hosts 文件..."
    # 遍历配置文件更新所有域名
    while read -r domain_group; do
        # 删除旧记录
        sed -i "/ ${domain_group}$/d" /etc/hosts
        # 添加新记录
        echo "$best_ip $domain_group" >> /etc/hosts
    done < "$CONFIG_FILE"
    
    echo "✅ 所有域名已更新到最新IP: $best_ip"
}

# 查看托管列表
list_domains() {
    echo "当前托管的域名列表："
    cat "$CONFIG_FILE" | tr ' ' '\n' | sort -u
}

# 主流程
main() {
    [ "$(id -u)" -ne 0 ] && echo "需要root权限" && exit 1
    init_setup

    case $1 in
        "-add")
            [ -z "$2" ] && echo "需要域名参数" && exit 1
            add_domain "$2"
            ;;
        "-del")
            [ -z "$2" ] && echo "需要域名参数" && exit 1
            del_domain "$2"
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
