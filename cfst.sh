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
        "https://ghproxy.com/$config_url"
        "https://ghfast.top/$config_url"
        "https://ghproxy.net/$config_url"
        "https://gh-proxy.com/$config_url"
    )
    
    echo "📥 正在下载配置文件..." >&2
    for url in "${mirrors[@]}"; do
        if wget --show-progress --timeout=20 -O "${PT_SITES_ENC}.tmp" "$url"; then
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
            echo "❌ 无法安装 jq，请手动安装后重试"
            exit 1
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
        headers=$(curl -sI "https://$domain" --connect-timeout 10 | grep -i 'server:')
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
    echo "❌ $masked_domain: 无法获取响应头，请主动确认站点或 tracker 是否托管于 Cloudflare，手动修改 /etc/hosts 文件" >&2
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
        
        echo "✅ 域名处理完成，共 ${#domains[@]} 个域名" >&2
        printf "%s\n" "${domains[@]}"
    else
        echo "❌ 未找到加密的站点配置文件" >&2
        exit 1
    fi
}

# 初始化环境
init_setup() {
    echo "作者：端端🐱/Gotchaaa，玩得开心～"
    echo "感谢 windfree、tianting 帮助完善站点数据"
    echo "使用姿势请查阅：https://github.com/vanchKong/cloudflare"
    
    # 检查并安装依赖
    check_dependencies
    
    [ ! -d "$CF_DIR" ] && mkdir -p "$CF_DIR"
    
    # 首次运行时初始化 hosts 记录
    current_ip=$(get_current_ip)
    
    # 创建临时文件
    temp_hosts=$(mktemp)
    echo "📝 临时文件位置: $temp_hosts" >&2
    
    # 保留原有的非脚本添加的记录
    grep -v " ${current_ip} " /etc/hosts > "$temp_hosts"
    
    # 按顺序添加新域名
    domains=($(load_pt_domains))
    for domain in "${domains[@]}"; do
        echo "${current_ip} ${domain}" >> "$temp_hosts"
    done
    
    # 替换原文件
    mv "$temp_hosts" /etc/hosts
    
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
    # 检测格式并去重
    if grep -q " ${domain}$" /etc/hosts; then
        echo "⚠️ 域名已存在: $domain" 
        return
    fi
    
    if check_domain_headers "$domain" "true"; then
        # 更新hosts
        current_ip=$(get_current_ip)
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

# 查看托管列表
list_domains() {
    echo "当前托管的域名列表："
    if [ -f "$PT_SITES_ENC" ]; then
        # 解密文件
        if ! openssl enc -aes-256-cbc -pbkdf2 -d -salt -in "$PT_SITES_ENC" -out "$PT_SITES_FILE" -pass pass:"$ENCRYPTION_KEY"; then
            echo "❌ 解密文件失败" >&2
            exit 1
        fi

        # 读取所有域名
        while IFS= read -r line; do
            if [ -z "$line" ]; then
                continue
            fi
            domain=$(echo "$line" | jq -r '.domain // empty')
            if [ -z "$domain" ]; then
                continue
            fi
            # 从 hosts 文件中获取 IP
            ip=$(grep " ${domain}$" /etc/hosts | awk '{print $1}')
            if [ ! -z "$ip" ]; then
                echo "$ip $domain"
            fi
        done < <(jq -c '.sites[].domains[], .sites[].trackers[]' "$PT_SITES_FILE")
        
        # 清理临时文件
        rm -f "$PT_SITES_FILE"
    else
        echo "❌ 未找到加密的站点配置文件" >&2
        exit 1
    fi
}

# 执行优选并更新所有域名
run_update() {
    echo "⏳ 开始优选测试..."
    cd "$CF_DIR" && ./CloudflareST -dn 8 -tl 400 -sl 1
    
    local best_ip=$(get_current_ip)
    [ -z "$best_ip" ] && echo "❌ 优选失败" && exit 1
    
    echo "🔄 正在更新 hosts 文件..."
    # 从 hosts 文件中获取所有域名并更新 IP
    while IFS= read -r line; do
        # 跳过注释行和空行
        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
        # 提取域名
        domain=$(echo "$line" | awk '{print $2}')
        if [ ! -z "$domain" ]; then
            # 删除旧记录
            sed -i "/ ${domain}$/d" /etc/hosts
            # 添加新记录
            echo "$best_ip $domain" >> /etc/hosts
        fi
    done < /etc/hosts
    
    echo "✅ 所有域名已更新到最新IP: $best_ip"
}

# 主流程
main() {
    [ "$(id -u)" -ne 0 ] && echo "需要root权限" && exit 1
    
    # 尝试下载并更新配置文件
    download_config
    
    # 检查配置文件是否存在
    check_config

    case "$1" in
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
            init_setup
            run_update
            ;;
    esac
}

main "$@"
