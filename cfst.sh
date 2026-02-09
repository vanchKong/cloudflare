# bash encrypt_pt_sites.sh encrypt
#!/bin/bash

# Cloudflare IP 优选管理脚本 (无标记版)
# 更新：支持批量添加/删除域名（空格/逗号分隔）
# 使用方法：保持与之前一致，参数可传入多个域名

# 配置参数
CF_DIR="/opt/CloudflareST"
CF_BIN="${CF_DIR}/CloudflareST"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PT_SITES_FILE="${SCRIPT_DIR}/pt_sites.json"
PT_SITES_ENC="${SCRIPT_DIR}/pt_sites.enc"
ENCRYPTION_KEY="dqwoidjdaksnkjrn@938475"

# 下载配置文件
download_config() {
    local config_url="https://raw.githubusercontent.com/vanchKong/cloudflare/refs/heads/main/pt_sites.enc"
    local mirrors=(
        "$config_url"
        "https://hk.gh-proxy.com/$config_url"
        "https://gh-proxy.com/$config_url"
        "https://cdn.gh-proxy.com/$config_url"
        "https://edgeone.gh-proxy.com/$config_url"
        "https://ghfast.top/$config_url"
        "https://ghproxy.net/$config_url"
    )
    
    echo "📥 正在下载配置文件..." >&2
    for url in "${mirrors[@]}"; do
        if wget --tries=2 --waitretry=1 --show-progress --timeout=20 -O "${PT_SITES_ENC}.tmp" "$url"; then
            # 验证下载的文件是否可解密
            if openssl enc -aes-256-cbc -pbkdf2 -d -salt -in "${PT_SITES_ENC}.tmp" -out "$PT_SITES_FILE" -pass pass:"$ENCRYPTION_KEY" 2>/dev/null; then
                mv "${PT_SITES_ENC}.tmp" "$PT_SITES_ENC"
                rm -f "$PT_SITES_FILE"
                echo "✅ 配置文件更新成功" >&2
                return 0
            fi
        fi
    done
    
    rm -f "${PT_SITES_ENC}.tmp"
    echo "⚠️ 配置文件下载失败，将使用本地文件" >&2
    return 1
}

# 检查配置文件
check_config() {
    if [ ! -f "$PT_SITES_ENC" ]; then
        echo "❌ 未找到配置文件，请确保 pt_sites.enc 文件存在" >&2
        exit 1
    fi
}

# 域名隐私处理
mask_domain() {
    local domain=$1
    local tld=$(echo "$domain" | grep -o '[^.]*$')
    local masked_tld=$(printf '%*s' ${#tld} '' | tr ' ' 'x')
    echo "${domain%.*}.$masked_tld"
}

# 检查并安装依赖
check_dependencies() {
    # 检查 jq
    if ! command -v jq &> /dev/null; then
        echo "正在安装 jq..."
        if command -v apt-get &> /dev/null; then
            apt-get update -o Acquire::AllowInsecureRepositories=true -o Acquire::AllowDowngradeToInsecureRepositories=true 2>/dev/null
            apt-get install -y jq 2>/dev/null
        elif command -v yum &> /dev/null; then
            yum install -y jq 2>/dev/null
        elif command -v dnf &> /dev/null; then
            dnf install -y jq 2>/dev/null
        elif command -v pacman &> /dev/null; then
            pacman -Sy --noconfirm jq 2>/dev/null
        elif command -v brew &> /dev/null; then
            brew install jq 2>/dev/null
        else
            echo "尝试直接下载 jq 二进制文件..."
            # 获取系统架构
            local arch=$(setup_arch)
            local base_url=""
            
            case "$arch" in
                "amd64")
                    base_url="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64"
                    ;;
                "arm64")
                    base_url="https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-arm64"
                    ;;
                *)
                    echo "❌ 不支持的架构: $arch"
                    exit 1
                    ;;
            esac
            
            # 设置镜像源
            local mirrors=(
                "$base_url"
                "https://hk.gh-proxy.com/$base_url"
                "https://gh-proxy.com/$base_url"
                "https://cdn.gh-proxy.com/$base_url"
                "https://edgeone.gh-proxy.com/$base_url"
                "https://ghfast.top/$base_url"
                "https://ghproxy.net/$base_url"
            )
            
            # 尝试从镜像下载
            local download_success=false
            for url in "${mirrors[@]}"; do
                if wget --tries=2 --waitretry=1 --show-progress --timeout=20 -O "/usr/bin/jq" "$url"; then
                    chmod +x "/usr/bin/jq"
                    echo "✅ jq 安装成功"
                    download_success=true
                    break
                fi
            done
            
            if [ "$download_success" = false ]; then
                echo "❌ jq 下载失败，请手动安装后重试"
                exit 1
            fi
        fi
        
        # 验证安装是否成功
        if ! command -v jq &> /dev/null; then
            echo "❌ jq 安装失败，请手动安装后重试"
            exit 1
        fi
    fi
}

# 架构检测
setup_arch() {
    case $(uname -m) in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *)       echo "unsupported" ;;
    esac
}

# 检查域名响应头
check_domain_headers() {
    local domain=$1
    local expected_cf=$2
    local max_retries=3
    local retry_count=0
    local headers=""
    local masked_domain=$(mask_domain "$domain")
    
    echo "🔍 检查域名: $masked_domain" >&2
    while [ $retry_count -lt $max_retries ]; do
        echo -n "." >&2
        headers=$(timeout 10 curl -sI "https://$domain" --connect-timeout 10 | grep -i 'server:')
        if [ ! -z "$headers" ]; then
            echo >&2  # 换行
            if [[ "$headers" =~ [Cc]loudflare ]]; then
                if [ "$expected_cf" = "false" ]; then
                    echo "⚠️ $masked_domain: 实际为 Cloudflare 托管，但配置文件中设置为非托管" >&2
                fi
                echo "✅ $masked_domain: Cloudflare 托管" >&2
                echo "cf"
            else
                if [ "$expected_cf" = "true" ]; then
                    echo "⚠️ $masked_domain: 实际非 Cloudflare 托管，但配置文件中设置为托管" >&2
                fi
                echo "ℹ️ $masked_domain: 非 Cloudflare 托管" >&2
                echo "non-cf"
            fi
            return 0
        fi
        retry_count=$((retry_count + 1))
        [ $retry_count -lt $max_retries ] && echo "⚠️ $masked_domain: 第 $retry_count 次重试..." >&2 && sleep 2
    done
    
    echo >&2  # 换行
    echo "❌ $masked_domain: 无法获取响应头，根据预设配置决定是否强制添加优选，不保证绝对正确！可主动确认该域名是否托管于 Cloudflare，手动修改 /etc/hosts 文件" >&2
    echo "unknown"
    return 1
}

# 获取当前优选IP
get_current_ip() {
    if [ -f "${CF_DIR}/result.csv" ]; then
        awk -F ',' 'NR==2 {print $1}' "${CF_DIR}/result.csv"
    else
        # 如果没有优选结果，返回默认IP
        echo "1.1.1.1"
    fi
}

# 从加密文件加载 PT 站点域名
load_pt_domains() {
    local check_cf=${1:-false}  # 默认不检查 CF 托管状态
    
    if [ -f "$PT_SITES_ENC" ]; then
        echo "📦 正在解密配置文件..." >&2
        # 解密文件
        if ! openssl enc -aes-256-cbc -pbkdf2 -d -salt -in "$PT_SITES_ENC" -out "$PT_SITES_FILE" -pass pass:"$ENCRYPTION_KEY"; then
            echo "❌ 解密文件失败" >&2
            exit 1
        fi

        echo "🔍 验证 JSON 格式..." >&2
        # 验证 JSON 文件格式
        if ! jq empty "$PT_SITES_FILE" 2>/dev/null; then
            echo "❌ JSON 文件格式错误" >&2
            exit 1
        fi
        
        # 读取所有域名并检查状态
        local domains=()
        local site_count=$(jq '.sites | length' "$PT_SITES_FILE")
        echo "📊 发现 $site_count 个站点" >&2
        
        # 计算总域名数
        local total_domains=$(jq '[.sites[].domains[], .sites[].trackers[]] | length' "$PT_SITES_FILE")
        local current_domain=0
        
        for ((i=0; i<$site_count; i++)); do
            local site_name=$(jq -r ".sites[$i].name" "$PT_SITES_FILE")
            echo "🌐 处理站点: $site_name" >&2
            # 获取当前站点的所有域名
            local site_domains=()
            
            # 处理主域名
            while IFS= read -r line; do
                if [ -z "$line" ]; then
                    continue
                fi
                domain=$(echo "$line" | jq -r '.domain // empty')
                if [ -z "$domain" ]; then
                    continue
                fi
                is_cf=$(echo "$line" | jq -r '.is_cf // false')
                current_domain=$((current_domain + 1))
                
                if [ "$check_cf" = "true" ]; then
                    echo -n "[$current_domain/$total_domains] " >&2
                    # 检查域名状态
                    actual_status=$(check_domain_headers "$domain" "$is_cf")
                    
                    # 根据检查结果决定是否添加
                    if [ "$actual_status" = "unknown" ]; then
                        # 如果无法获取响应头，使用预设值
                        if [ "$is_cf" = "true" ]; then
                            echo "➕ 添加域名(预设): $(mask_domain "$domain")" >&2
                            site_domains+=("$domain")
                        fi
                    elif [ "$actual_status" = "cf" ]; then
                        # 如果确认是 CF 托管，添加域名
                        echo "➕ 添加域名(CF): $(mask_domain "$domain")" >&2
                        site_domains+=("$domain")
                    fi
                else
                    # 不检查 CF 托管状态，直接添加域名
                    site_domains+=("$domain")
                fi
            done < <(jq -c ".sites[$i].domains[]" "$PT_SITES_FILE")
            
            # 处理 tracker 域名
            while IFS= read -r line; do
                if [ -z "$line" ]; then
                    continue
                fi
                domain=$(echo "$line" | jq -r '.domain // empty')
                if [ -z "$domain" ]; then
                    continue
                fi
                is_cf=$(echo "$line" | jq -r '.is_cf // false')
                current_domain=$((current_domain + 1))
                
                if [ "$check_cf" = "true" ]; then
                    echo -n "[$current_domain/$total_domains] " >&2
                    # 检查域名状态
                    actual_status=$(check_domain_headers "$domain" "$is_cf")
                    
                    # 根据检查结果决定是否添加
                    if [ "$actual_status" = "unknown" ]; then
                        # 如果无法获取响应头，使用预设值
                        if [ "$is_cf" = "true" ]; then
                            echo "➕ 添加 tracker(预设): $(mask_domain "$domain")" >&2
                            site_domains+=("$domain")
                        fi
                    elif [ "$actual_status" = "cf" ]; then
                        # 如果确认是 CF 托管，添加域名
                        echo "➕ 添加 tracker(CF): $(mask_domain "$domain")" >&2
                        site_domains+=("$domain")
                    fi
                else
                    # 不检查 CF 托管状态，直接添加域名
                    site_domains+=("$domain")
                fi
            done < <(jq -c ".sites[$i].trackers[]" "$PT_SITES_FILE")
            
            # 将当前站点的所有域名添加到总列表
            domains+=("${site_domains[@]}")
        done
        
        # 清理临时文件
        rm -f "$PT_SITES_FILE"
        
        if [ ${#domains[@]} -eq 0 ]; then
            echo "❌ 没有找到有效的域名" >&2
            exit 1
        fi
        
        if [ "$check_cf" = "true" ]; then
            echo "✅ 域名处理完成，共 ${#domains[@]} 个域名" >&2
        fi
        printf "%s\n" "${domains[@]}"
    else
        echo "❌ 未找到加密的站点配置文件" >&2
        exit 1
    fi
}

# 初始化环境
init_setup() {
    
    [ ! -d "$CF_DIR" ] && mkdir -p "$CF_DIR"
    
    # 获取当前优选 IP
    current_ip=$(get_current_ip)
    
    # 加载并获取有效的域名列表
    domains=($(load_pt_domains true))
    
    # 删掉指向到当前优选 ip 的记录
    sed -i "/^${current_ip} /d" /etc/hosts
    # 原逻辑：删除加密文件中存在的域名的优选记录
    # for domain in "${domains[@]}"; do
    #     sed -i "/ ${domain}$/d" /etc/hosts
    # done
    
    # 重新添加加密文件中的域名记录
    for domain in "${domains[@]}"; do
        echo "${current_ip} ${domain}" >> /etc/hosts
    done
    
    echo "✅ 已初始化 hosts 文件"
    
}

# 域名有效性检测
# validate_domain() {
#     local domain=$1
#     echo "验证域名: $domain ..."
    
#     local headers=$(curl -sI "https://$domain" --connect-timeout 10 | grep -i 'server:')
#     if [[ "$headers" =~ [Cc]loudflare ]]; then
#         echo "✅ $domain 托管于 Cloudflare"
#         return 0
#     else
#         echo "ℹ️ $domain: 非 Cloudflare 托管"
#         return 1
#     fi
# }

# 添加单个域名
add_single_domain() {
    local domain=$1
    local current_ip=$(get_current_ip)

    # 检测格式并检查已存在的域名
    if grep -q " ${domain}$" /etc/hosts; then
        # 获取当前域名在 hosts 中的 IP
        local existing_ip=$(grep " ${domain}$" /etc/hosts | awk '{print $1}')
        
        # 验证域名是否托管在 Cloudflare
        local actual_status=$(check_domain_headers "$domain" "unknown")
        if [ "$actual_status" != "cf" ]; then
            echo "❌ 域名已存在但非 Cloudflare 托管: $domain"
            return
        fi
        
        if [ "$existing_ip" != "$current_ip" ]; then
            # 如果 IP 不同，更新为新优选 IP
            sed -i "s/^${existing_ip} ${domain}$/${current_ip} ${domain}/" /etc/hosts
            echo "🔄 更新域名 IP: $domain (${existing_ip} -> ${current_ip})"
        else
            echo "ℹ️ 域名已存在且 IP 已是最优: $domain"
        fi
        return
    fi

    # 1. 先尝试解密配置文件并查找预设
    local is_cf_preset=""
    if [ -f "$PT_SITES_ENC" ]; then
        if openssl enc -aes-256-cbc -pbkdf2 -d -salt -in "$PT_SITES_ENC" -out "$PT_SITES_FILE" -pass pass:"$ENCRYPTION_KEY" 2>/dev/null; then
            is_cf_preset=$(jq -r --arg d "$domain" '
                [.sites[].domains[], .sites[].trackers[]]
                | map(select(.domain == $d)) | .[0].is_cf // empty
            ' "$PT_SITES_FILE")
            rm -f "$PT_SITES_FILE"
        fi
    fi
    # 2. 判断逻辑
    if [ "$is_cf_preset" = "true" ] || [ "$is_cf_preset" = "false" ]; then
        # 有预设，直接用预设
        actual_status=$(check_domain_headers "$domain" "$is_cf_preset")
        if [ "$actual_status" = "cf" ] || { [ "$actual_status" = "unknown" ] && [ "$is_cf_preset" = "true" ]; }; then
            echo "$current_ip $domain" >> /etc/hosts
            echo "➕ 添加域名(预设): $domain" >&2
        else
            echo "❌ 跳过非CF域名: $domain" >&2
        fi
    else
        echo "$domain 预设 $is_cf_preset" >&2
        # 没有预设，按未知逻辑
        actual_status=$(check_domain_headers "$domain" "unknown")
        if [ "$actual_status" = "cf" ]; then
            echo "$current_ip $domain" >> /etc/hosts
            echo "➕ 添加域名(CF): $domain" >&2
        else
            echo "❌ 跳过无效域名: $domain" >&2
        fi
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

# 查看托管列表
list_domains() {
    echo "当前优选的域名列表："
    current_ip=$(get_current_ip)
    
    if [ -z "$current_ip" ]; then
        echo "❌ 未找到当前优选 IP" >&2
        exit 1
    fi
    
    # 从 hosts 文件中获取当前优选 IP 对应的所有域名
    if [ -f "/etc/hosts" ]; then
        grep "^${current_ip} " /etc/hosts | awk '{print $2}'
    else
        echo "❌ 未找到 hosts 文件" >&2
        exit 1
    fi
}

# 执行优选并更新所有域名
run_update() {
    # 下载 CloudflareST
    if [ ! -f "$CF_BIN" ]; then
        arch=$(setup_arch)
        [ "$arch" = "unsupported" ] && echo "不支持的架构" && exit 1
        
        filename="CloudflareST_linux_${arch}.tar.gz"
        mirrors=(
            "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://hk.gh-proxy.com/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://gh-proxy.com/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://cdn.gh-proxy.com/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://edgeone.gh-proxy.com/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://ghfast.top/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
            "https://ghproxy.net/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
        )

        for url in "${mirrors[@]}"; do
            if wget --tries=2 --waitretry=1 --show-progress --timeout=20 -O "${CF_DIR}/$filename" "$url"; then
                tar -zxf "${CF_DIR}/$filename" -C "$CF_DIR" && chmod +x "$CF_BIN"
                rm "${CF_DIR}/$filename"
                break
            fi
        done
        
        if [ ! -f "$CF_BIN" ]; then
            echo "❌ CloudflareST 下载失败" && exit 1
        fi
    fi

    # 获取当前优选 IP
    local current_ip=$(get_current_ip)
    [ -z "$current_ip" ] && echo "❌ 未找到当前优选 IP" && exit 1
    
    echo "⏳ 开始优选测试..."
    cd "$CF_DIR" && ./CloudflareST -dn 4 -tl 400 -sl 1
    
    # 获取新的优选 IP
    local best_ip=$(get_current_ip)
    [ -z "$best_ip" ] && echo "❌ 优选失败" && exit 1
    
    echo "🔄 正在更新 hosts 文件..."
    
    # 更新所有当前优选 IP 的记录到新的优选 IP
    sed -i "s/^${current_ip} /${best_ip} /" /etc/hosts
    
    echo "✅ 所有域名已更新到最新IP: $best_ip"
}

# 删除所有优选记录
del_all_domains() {
    echo "🗑️ 正在删除所有优选记录..."
    
    # 获取当前优选 IP
    local current_ip=$(get_current_ip)
    if [ -n "$current_ip" ]; then
        # 删除指向当前优选 IP 的记录
        sed -i "/^${current_ip} /d" /etc/hosts
        echo "✅ 已删除指向当前优选 IP ($current_ip) 的记录"
    fi
    
    # 获取加密文件中的所有域名
    local domains=($(load_pt_domains))
    if [ ${#domains[@]} -gt 0 ]; then
        # 删除加密文件中的域名记录
        for domain in "${domains[@]}"; do
            sed -i "/ ${domain}$/d" /etc/hosts
        done
        echo "✅ 已删除加密文件中的域名记录"
    fi
    
    echo "✅ 所有优选记录已清理完成"
}

# 主流程
main() {
    # 如果 /opt/cfst_hosts.sh、/opt/ipv6.txt、/opt/ip.txt 存在，则删除
    if [ -f "/opt/cfst_hosts.sh" ]; then
        rm -f "/opt/cfst_hosts.sh"
    fi
    if [ -f "/opt/ipv6.txt" ]; then
        rm -f "/opt/ipv6.txt"
    fi
    if [ -f "/opt/ip.txt" ]; then
        rm -f "/opt/ip.txt"
    fi
    # 如果存在非目录文件 /opt/CloudflareST 则删除
    if [ -f "/opt/CloudflareST" ]; then
        rm -f "/opt/CloudflareST"
    fi
    [ "$(id -u)" -ne 0 ] && echo "需要root权限" && exit 1
    

    case "$1" in
        "-add")
            shift
            download_config
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
        "-delall")
            download_config
            del_all_domains
            ;;
        "-list")
            list_domains
            ;;
        "-sync")
            # 仅通过加密文件更新域名，IP 指向当前优选 IP，不重新测速
            download_config
            check_config
            check_dependencies
            init_setup
            ;;
        *)
    # 尝试下载并更新配置文件
    download_config
    
    # 检查配置文件是否存在
    check_config
    # 检查并安装依赖
    check_dependencies

    echo "作者：端端🐱/Gotchaaa，玩得开心～"
    echo "感谢 windfree、tianting 帮助完善站点数据"
    echo "使用姿势请查阅：https://github.com/vanchKong/cloudflare"
    
    # 添加用户选择功能
    echo "请选择操作模式："
    echo "1. 重新载入并测速获取优选 IP（首次运行时请选择此项）"
    echo "2. 不重新载入域名，仅重新测速获取优选 IP"
    echo "3. 仅通过加密文件更新域名（使用当前优选 IP，不测速）"
    read -p "请输入选项 [1/2/3]: " choice
    
    case "$choice" in
        1)
            echo "🔄 执行完整更新流程..."
            init_setup
            run_update
            ;;
        2)
            echo "🔄 仅执行测速更新..."
            run_update
            ;;
        3)
            echo "🔄 仅同步加密文件中的域名到 hosts（当前优选 IP）..."
            init_setup
            ;;
        *)
            echo "❌ 无效的选项，请重新运行脚本"
            exit 1
            ;;
    esac
    ;;
    esac
}

main "$@"
