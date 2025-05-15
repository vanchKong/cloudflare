# Cloudflare IP 优选管理脚本 (Windows PowerShell 版)
# 使用方法：
# 1. 以管理员权限运行 PowerShell
# 2. 执行 .\cfst.ps1 命令

# 配置参数
$CF_DIR = "C:\CloudflareST"
$CF_BIN = "$CF_DIR\CloudflareST.exe"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PT_SITES_FILE = Join-Path $SCRIPT_DIR "pt_sites.json"
$PT_SITES_ENC = Join-Path $SCRIPT_DIR "pt_sites.enc"
$ENCRYPTION_KEY = "dqwoidjdaksnkjrn@938475"
$HOSTS_FILE = "$env:windir\System32\drivers\etc\hosts"

# 域名隐私处理
function Mask-Domain {
    param([string]$domain)
    $tld = $domain.Split('.')[-1]
    $maskedTld = 'x' * $tld.Length
    return $domain.Substring(0, $domain.LastIndexOf('.')) + '.' + $maskedTld
}

# 检查并安装依赖
function Check-Dependencies {
    # 检查 jq
    if (-not (Get-Command jq -ErrorAction SilentlyContinue)) {
        Write-Host "正在安装 jq..."
        # 使用 winget 安装 jq
        winget install -e --id stedolan.jq
        if (-not $?) {
            Write-Host "❌ 无法安装 jq，请手动安装后重试"
            exit 1
        }
    }
}

# 下载配置文件
function Download-Config {
    $configUrl = "https://raw.githubusercontent.com/vanchKong/cloudflare/refs/heads/main/pt_sites.enc"
    $mirrors = @(
        $configUrl,
        "https://ghproxy.com/$configUrl",
        "https://ghfast.top/$configUrl",
        "https://ghproxy.net/$configUrl",
        "https://gh-proxy.com/$configUrl"
    )
    
    Write-Host "📥 正在下载配置文件..." -ForegroundColor Yellow
    foreach ($url in $mirrors) {
        try {
            Invoke-WebRequest -Uri $url -OutFile "$PT_SITES_ENC.tmp" -TimeoutSec 20
            # 验证下载的文件是否可解密
            $decrypted = & openssl enc -aes-256-cbc -pbkdf2 -d -salt -in "$PT_SITES_ENC.tmp" -out "$PT_SITES_FILE" -pass "pass:$ENCRYPTION_KEY" 2>$null
            if ($?) {
                Move-Item -Force "$PT_SITES_ENC.tmp" $PT_SITES_ENC
                Remove-Item -Force $PT_SITES_FILE -ErrorAction SilentlyContinue
                Write-Host "✅ 配置文件更新成功" -ForegroundColor Green
                return $true
            }
        }
        catch {
            continue
        }
    }
    
    Remove-Item -Force "$PT_SITES_ENC.tmp" -ErrorAction SilentlyContinue
    Write-Host "⚠️ 配置文件下载失败，将使用本地文件" -ForegroundColor Yellow
    return $false
}

# 检查配置文件
function Check-Config {
    if (-not (Test-Path $PT_SITES_ENC)) {
        Write-Host "❌ 未找到配置文件，请确保 pt_sites.enc 文件存在" -ForegroundColor Red
        exit 1
    }
}

# 获取当前优选IP
function Get-CurrentIP {
    if (Test-Path "$CF_DIR\result.csv") {
        return (Get-Content "$CF_DIR\result.csv" | Select-Object -Skip 1 | Select-Object -First 1).Split(',')[0]
    }
    return "1.1.1.1"
}

# 检查域名响应头
function Check-DomainHeaders {
    param(
        [string]$domain,
        [string]$expectedCf
    )
    
    $maskedDomain = Mask-Domain $domain
    Write-Host "🔍 检查域名: $maskedDomain" -ForegroundColor Yellow
    
    $maxRetries = 3
    $retryCount = 0
    
    while ($retryCount -lt $maxRetries) {
        try {
            $response = Invoke-WebRequest -Uri "https://$domain" -Method Head -TimeoutSec 10
            $server = $response.Headers["Server"]
            
            if ($server -match "cloudflare") {
                if ($expectedCf -eq "false") {
                    Write-Host "⚠️ $maskedDomain: 实际为 Cloudflare 托管，但配置文件中设置为非托管" -ForegroundColor Yellow
                }
                Write-Host "✅ $maskedDomain: Cloudflare 托管" -ForegroundColor Green
                return "cf"
            }
            else {
                if ($expectedCf -eq "true") {
                    Write-Host "⚠️ $maskedDomain: 实际非 Cloudflare 托管，但配置文件中设置为托管" -ForegroundColor Yellow
                }
                Write-Host "ℹ️ $maskedDomain: 非 Cloudflare 托管" -ForegroundColor Cyan
                return "non-cf"
            }
        }
        catch {
            $retryCount++
            if ($retryCount -lt $maxRetries) {
                Write-Host "⚠️ $maskedDomain: 第 $retryCount 次重试..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
        }
    }
    
    Write-Host "❌ $maskedDomain: 无法获取响应头，根据预设配置决定是否强制添加优选，不保证绝对正确！可主动确认该域名是否托管于 Cloudflare，手动修改 hosts 文件" -ForegroundColor Red
    return "unknown"
}

# 从加密文件加载 PT 站点域名
function Load-PTDomains {
    if (Test-Path $PT_SITES_ENC) {
        Write-Host "📦 正在解密配置文件..." -ForegroundColor Yellow
        # 解密文件
        $decrypted = & openssl enc -aes-256-cbc -pbkdf2 -d -salt -in $PT_SITES_ENC -out $PT_SITES_FILE -pass "pass:$ENCRYPTION_KEY"
        if (-not $?) {
            Write-Host "❌ 解密文件失败" -ForegroundColor Red
            exit 1
        }

        Write-Host "🔍 验证 JSON 格式..." -ForegroundColor Yellow
        # 验证 JSON 文件格式
        $json = Get-Content $PT_SITES_FILE | ConvertFrom-Json
        if (-not $?) {
            Write-Host "❌ JSON 文件格式错误" -ForegroundColor Red
            exit 1
        }
        
        # 读取所有域名并检查状态
        $domains = @()
        $siteCount = $json.sites.Count
        Write-Host "📊 发现 $siteCount 个站点" -ForegroundColor Yellow
        
        # 计算总域名数
        $totalDomains = ($json.sites | ForEach-Object { $_.domains.Count + $_.trackers.Count } | Measure-Object -Sum).Sum
        $currentDomain = 0
        
        foreach ($site in $json.sites) {
            Write-Host "🌐 处理站点: $($site.name)" -ForegroundColor Yellow
            $siteDomains = @()
            
            # 处理主域名
            foreach ($domain in $site.domains) {
                if (-not $domain.domain) { continue }
                $currentDomain++
                Write-Host -NoNewline "[$currentDomain/$totalDomains] " -ForegroundColor Yellow
                
                # 检查域名状态
                $actualStatus = Check-DomainHeaders $domain.domain $domain.is_cf
                
                # 根据检查结果决定是否添加
                if ($actualStatus -eq "unknown") {
                    if ($domain.is_cf -eq "true") {
                        Write-Host "➕ 添加域名(预设): $(Mask-Domain $domain.domain)" -ForegroundColor Green
                        $siteDomains += $domain.domain
                    }
                }
                elseif ($actualStatus -eq "cf") {
                    Write-Host "➕ 添加域名(CF): $(Mask-Domain $domain.domain)" -ForegroundColor Green
                    $siteDomains += $domain.domain
                }
            }
            
            # 处理 tracker 域名
            foreach ($tracker in $site.trackers) {
                if (-not $tracker.domain) { continue }
                $currentDomain++
                Write-Host -NoNewline "[$currentDomain/$totalDomains] " -ForegroundColor Yellow
                
                # 检查域名状态
                $actualStatus = Check-DomainHeaders $tracker.domain $tracker.is_cf
                
                # 根据检查结果决定是否添加
                if ($actualStatus -eq "unknown") {
                    if ($tracker.is_cf -eq "true") {
                        Write-Host "➕ 添加 tracker(预设): $(Mask-Domain $tracker.domain)" -ForegroundColor Green
                        $siteDomains += $tracker.domain
                    }
                }
                elseif ($actualStatus -eq "cf") {
                    Write-Host "➕ 添加 tracker(CF): $(Mask-Domain $tracker.domain)" -ForegroundColor Green
                    $siteDomains += $tracker.domain
                }
            }
            
            # 将当前站点的所有域名添加到总列表
            $domains += $siteDomains
        }
        
        # 清理临时文件
        Remove-Item -Force $PT_SITES_FILE -ErrorAction SilentlyContinue
        
        if ($domains.Count -eq 0) {
            Write-Host "❌ 没有找到有效的域名" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "✅ 域名处理完成，共 $($domains.Count) 个域名" -ForegroundColor Green
        return $domains
    }
    else {
        Write-Host "❌ 未找到加密的站点配置文件" -ForegroundColor Red
        exit 1
    }
}

# 初始化环境
function Init-Setup {
    Write-Host "作者：端端🐱/Gotchaaa，玩得开心～" -ForegroundColor Cyan
    Write-Host "感谢 windfree、tianting 帮助完善站点数据" -ForegroundColor Cyan
    Write-Host "使用姿势请查阅：https://github.com/vanchKong/cloudflare" -ForegroundColor Cyan
    
    # 检查并安装依赖
    Check-Dependencies
    
    if (-not (Test-Path $CF_DIR)) {
        New-Item -ItemType Directory -Path $CF_DIR | Out-Null
    }
    
    # 首次运行时初始化 hosts 记录
    $currentIP = Get-CurrentIP
    
    # 删除所有当前优选 IP 的记录
    if ($currentIP) {
        Write-Host "🗑️ 清理当前优选 IP 记录..." -ForegroundColor Yellow
        $hostsContent = Get-Content $HOSTS_FILE
        $hostsContent | Where-Object { -not $_.StartsWith($currentIP) } | Set-Content $HOSTS_FILE
    }
    
    # 按顺序添加新域名
    $domains = Load-PTDomains
    foreach ($domain in $domains) {
        Add-Content -Path $HOSTS_FILE -Value "$currentIP $domain"
    }
    
    Write-Host "✅ 已初始化 hosts 文件" -ForegroundColor Green
    
    # 下载 CloudflareST
    if (-not (Test-Path $CF_BIN)) {
        $arch = if ([Environment]::Is64BitOperatingSystem) { "amd64" } else { "386" }
        $filename = "CloudflareST_windows_$arch.zip"
        $mirrors = @(
            "https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename",
            "https://ghproxy.com/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename",
            "https://ghfast.top/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename",
            "https://ghproxy.net/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename",
            "https://gh-proxy.com/https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/$filename"
        )

        foreach ($url in $mirrors) {
            try {
                Invoke-WebRequest -Uri $url -OutFile "$CF_DIR\$filename" -TimeoutSec 20
                Expand-Archive -Path "$CF_DIR\$filename" -DestinationPath $CF_DIR -Force
                Remove-Item -Force "$CF_DIR\$filename"
                return
            }
            catch {
                continue
            }
        }
        Write-Host "下载失败" -ForegroundColor Red
        exit 1
    }
}

# 添加单个域名
function Add-SingleDomain {
    param([string]$domain)
    
    # 检测格式并去重
    if ((Get-Content $HOSTS_FILE) -match " $domain$") {
        Write-Host "⚠️ 域名已存在: $domain" -ForegroundColor Yellow
        return
    }
    
    $status = Check-DomainHeaders $domain "true"
    if ($status -eq "cf" -or $status -eq "unknown") {
        # 更新hosts
        $currentIP = Get-CurrentIP
        Add-Content -Path $HOSTS_FILE -Value "$currentIP $domain"
        Write-Host "✅ 已添加域名: $domain" -ForegroundColor Green
    }
    else {
        Write-Host "❌ 跳过无效域名: $domain" -ForegroundColor Red
    }
}

# 删除单个域名
function Remove-SingleDomain {
    param([string]$domain)
    
    # 从hosts中删除
    $hostsContent = Get-Content $HOSTS_FILE
    $newContent = $hostsContent | Where-Object { -not $_.EndsWith(" $domain") }
    if ($newContent.Count -ne $hostsContent.Count) {
        $newContent | Set-Content $HOSTS_FILE
        Write-Host "✅ 已移除域名: $domain" -ForegroundColor Green
    }
    else {
        Write-Host "⚠️ 域名不存在: $domain" -ForegroundColor Yellow
    }
}

# 查看托管列表
function List-Domains {
    Write-Host "当前托管的域名列表：" -ForegroundColor Cyan
    if (Test-Path $PT_SITES_ENC) {
        # 解密文件
        $decrypted = & openssl enc -aes-256-cbc -pbkdf2 -d -salt -in $PT_SITES_ENC -out $PT_SITES_FILE -pass "pass:$ENCRYPTION_KEY"
        if (-not $?) {
            Write-Host "❌ 解密文件失败" -ForegroundColor Red
            exit 1
        }

        # 读取所有域名
        $json = Get-Content $PT_SITES_FILE | ConvertFrom-Json
        foreach ($site in $json.sites) {
            foreach ($domain in $site.domains) {
                if ($domain.domain) {
                    $ip = (Get-Content $HOSTS_FILE | Where-Object { $_ -match " $($domain.domain)$" } | ForEach-Object { $_.Split()[0] })
                    if ($ip) {
                        Write-Host "$ip $($domain.domain)"
                    }
                }
            }
            foreach ($tracker in $site.trackers) {
                if ($tracker.domain) {
                    $ip = (Get-Content $HOSTS_FILE | Where-Object { $_ -match " $($tracker.domain)$" } | ForEach-Object { $_.Split()[0] })
                    if ($ip) {
                        Write-Host "$ip $($tracker.domain)"
                    }
                }
            }
        }
        
        # 清理临时文件
        Remove-Item -Force $PT_SITES_FILE -ErrorAction SilentlyContinue
    }
    else {
        Write-Host "❌ 未找到加密的站点配置文件" -ForegroundColor Red
        exit 1
    }
}

# 执行优选并更新所有域名
function Run-Update {
    Write-Host "⏳ 开始优选测试..." -ForegroundColor Yellow
    Set-Location $CF_DIR
    & $CF_BIN -dn 8 -tl 400 -sl 1
    
    $bestIP = Get-CurrentIP
    if (-not $bestIP) {
        Write-Host "❌ 优选失败" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "🔄 正在更新 hosts 文件..." -ForegroundColor Yellow
    # 从 hosts 文件中获取所有域名并更新 IP
    $hostsContent = Get-Content $HOSTS_FILE
    $currentIP = Get-CurrentIP
    
    foreach ($line in $hostsContent) {
        # 跳过注释行和空行
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { continue }
        
        # 提取域名和 IP
        $parts = $line -split '\s+'
        if ($parts.Count -ge 2) {
            $ip = $parts[0]
            $domain = $parts[1]
            
            # 只更新之前优选 IP 和 1.1.1.1 的记录
            if ($ip -eq "1.1.1.1" -or $ip -eq $currentIP) {
                # 删除旧记录
                $hostsContent = $hostsContent | Where-Object { -not $_.EndsWith(" $domain") }
                # 添加新记录
                $hostsContent += "$bestIP $domain"
            }
        }
    }
    
    $hostsContent | Set-Content $HOSTS_FILE
    Write-Host "✅ 所有域名已更新到最新IP: $bestIP" -ForegroundColor Green
}

# 主流程
function Main {
    # 检查管理员权限
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "需要管理员权限" -ForegroundColor Red
        exit 1
    }

    $args = $MyInvocation.UnboundArguments
    switch ($args[0]) {
        "-add" {
            if ($args.Count -lt 2) {
                Write-Host "需要域名参数" -ForegroundColor Red
                exit 1
            }
            $domains = $args[1..($args.Count-1)] -join ' ' -split '[,\s]+'
            foreach ($domain in $domains) {
                Add-SingleDomain $domain
            }
        }
        "-del" {
            if ($args.Count -lt 2) {
                Write-Host "需要域名参数" -ForegroundColor Red
                exit 1
            }
            $domains = $args[1..($args.Count-1)] -join ' ' -split '[,\s]+'
            foreach ($domain in $domains) {
                Remove-SingleDomain $domain
            }
        }
        "-list" {
            List-Domains
        }
        default {
            # 尝试下载并更新配置文件
            Download-Config
            
            # 检查配置文件是否存在
            Check-Config
            
            Init-Setup
            Run-Update
        }
    }
}

# 执行主流程
Main 