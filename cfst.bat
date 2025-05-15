@echo off
setlocal enabledelayedexpansion

:: 检查管理员权限
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo 需要管理员权限
    exit /b 1
)

:: 配置参数
set "CF_DIR=%ProgramFiles%\CloudflareST"
set "CF_BIN=%CF_DIR%\CloudflareST.exe"
set "SCRIPT_DIR=%~dp0"
set "PT_SITES_FILE=%SCRIPT_DIR%pt_sites.json"
set "PT_SITES_ENC=%SCRIPT_DIR%pt_sites.enc"
set "ENCRYPTION_KEY=dqwoidjdaksnkjrn@938475"
set "HOSTS_FILE=%SystemRoot%\System32\drivers\etc\hosts"

:: 检查并安装依赖
where jq >nul 2>&1
if %errorLevel% neq 0 (
    echo 正在安装 jq...
    powershell -Command "& {Invoke-WebRequest -Uri 'https://github.com/stedolan/jq/releases/download/jq-1.6/jq-win64.exe' -OutFile '%CF_DIR%\jq.exe'}"
    if %errorLevel% neq 0 (
        echo ❌ 无法安装 jq，请手动安装后重试
        exit /b 1
    )
)

:: 下载配置文件
:download_config
echo 📥 正在下载配置文件...
set "config_url=https://raw.githubusercontent.com/vanchKong/cloudflare/refs/heads/main/pt_sites.enc"
set "mirrors[0]=%config_url%"
set "mirrors[1]=https://ghproxy.com/%config_url%"
set "mirrors[2]=https://ghfast.top/%config_url%"
set "mirrors[3]=https://ghproxy.net/%config_url%"
set "mirrors[4]=https://gh-proxy.com/%config_url%"

for /L %%i in (0,1,4) do (
    powershell -Command "& {Invoke-WebRequest -Uri '!mirrors[%%i]!' -OutFile '%PT_SITES_ENC%.tmp'}"
    if %errorLevel% equ 0 (
        :: 验证文件是否可解密
        openssl enc -aes-256-cbc -pbkdf2 -d -salt -in "%PT_SITES_ENC%.tmp" -out "%PT_SITES_FILE%" -pass pass:"%ENCRYPTION_KEY%" >nul 2>&1
        if %errorLevel% equ 0 (
            move /y "%PT_SITES_ENC%.tmp" "%PT_SITES_ENC%" >nul
            del /f /q "%PT_SITES_FILE%" >nul 2>&1
            echo ✅ 配置文件更新成功
            goto :config_downloaded
        )
    )
)

echo ⚠️ 配置文件下载失败，将使用本地文件
:config_downloaded

:: 检查配置文件是否存在
if not exist "%PT_SITES_ENC%" (
    echo ❌ 未找到配置文件，请确保 pt_sites.enc 文件存在
    exit /b 1
)

:: 主流程
if "%1"=="" (
    call :init_setup
    call :run_update
    goto :eof
)

if "%1"=="-add" (
    if "%2"=="" (
        echo 需要域名参数
        exit /b 1
    )
    call :add_single_domain %2
    goto :eof
)

if "%1"=="-del" (
    if "%2"=="" (
        echo 需要域名参数
        exit /b 1
    )
    call :del_single_domain %2
    goto :eof
)

if "%1"=="-list" (
    call :list_domains
    goto :eof
)

:: 初始化环境
:init_setup
echo 作者：端端🐱/Gotchaaa，玩得开心～
echo 感谢 windfree、tianting 帮助完善站点数据
echo 使用姿势请查阅：https://github.com/vanchKong/cloudflare

if not exist "%CF_DIR%" mkdir "%CF_DIR%"

:: 首次运行时初始化 hosts 记录
for /f "tokens=1" %%a in ('type "%CF_DIR%\result.csv" ^| findstr /r "^[0-9]"') do set "current_ip=%%a"
if "%current_ip%"=="" set "current_ip=1.1.1.1"

:: 删除所有当前优选 IP 的记录
echo 🗑️ 清理当前优选 IP 记录...
powershell -Command "& {(Get-Content '%HOSTS_FILE%') | Where-Object {$_ -notmatch '^%current_ip% '} | Set-Content '%HOSTS_FILE%'}"

:: 按顺序添加新域名
for /f "tokens=*" %%a in ('jq -r ".sites[].domains[].domain, .sites[].trackers[].domain" "%PT_SITES_FILE%"') do (
    if not "%%a"=="" (
        echo %current_ip% %%a>> "%HOSTS_FILE%"
    )
)

echo ✅ 已初始化 hosts 文件

:: 下载 CloudflareST
if not exist "%CF_BIN%" (
    echo 正在下载 CloudflareST...
    powershell -Command "& {Invoke-WebRequest -Uri 'https://github.com/XIU2/CloudflareSpeedTest/releases/download/v2.2.5/CloudflareST_windows_amd64.zip' -OutFile '%CF_DIR%\CloudflareST.zip'}"
    if %errorLevel% equ 0 (
        powershell -Command "& {Expand-Archive -Path '%CF_DIR%\CloudflareST.zip' -DestinationPath '%CF_DIR%' -Force}"
        del /f /q "%CF_DIR%\CloudflareST.zip"
    ) else (
        echo 下载失败
        exit /b 1
    )
)
goto :eof

:: 执行优选并更新所有域名
:run_update
echo ⏳ 开始优选测试...
cd /d "%CF_DIR%" && CloudflareST.exe -dn 8 -tl 400 -sl 1

for /f "tokens=1" %%a in ('type "result.csv" ^| findstr /r "^[0-9]"') do set "best_ip=%%a"
if "%best_ip%"=="" (
    echo ❌ 优选失败
    exit /b 1
)

echo 🔄 正在更新 hosts 文件...
:: 更新 hosts 文件中的记录
powershell -Command "& {(Get-Content '%HOSTS_FILE%') | ForEach-Object {if ($_ -match '^1\.1\.1\.1 ' -or $_ -match '^%current_ip% ') {$_ -replace '^[0-9\.]+ ', '%best_ip% '} else {$_}} | Set-Content '%HOSTS_FILE%'}"

echo ✅ 所有域名已更新到最新IP: %best_ip%
goto :eof

:: 添加单个域名
:add_single_domain
set "domain=%2"
findstr /c:" %domain%" "%HOSTS_FILE%" >nul
if %errorLevel% equ 0 (
    echo ⚠️ 域名已存在: %domain%
    goto :eof
)

:: 检查域名是否托管于 Cloudflare
curl -sI "https://%domain%" | findstr /i "server:" | findstr /i "cloudflare" >nul
if %errorLevel% equ 0 (
    for /f "tokens=1" %%a in ('type "%CF_DIR%\result.csv" ^| findstr /r "^[0-9]"') do set "current_ip=%%a"
    if "%current_ip%"=="" set "current_ip=1.1.1.1"
    echo %current_ip% %domain%>> "%HOSTS_FILE%"
    echo ✅ 已添加域名: %domain%
) else (
    echo ❌ 跳过无效域名: %domain%
)
goto :eof

:: 删除单个域名
:del_single_domain
set "domain=%2"
findstr /c:" %domain%" "%HOSTS_FILE%" >nul
if %errorLevel% equ 0 (
    powershell -Command "& {(Get-Content '%HOSTS_FILE%') | Where-Object {$_ -notmatch ' %domain%$'} | Set-Content '%HOSTS_FILE%'}"
    echo ✅ 已移除域名: %domain%
) else (
    echo ⚠️ 域名不存在: %domain%
)
goto :eof

:: 查看托管列表
:list_domains
echo 当前托管的域名列表：
for /f "tokens=1,2" %%a in ('type "%HOSTS_FILE%"') do (
    if not "%%b"=="" (
        echo %%a %%b
    )
)
goto :eof 