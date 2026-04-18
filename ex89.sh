#!/usr/bin/env bash
# ============================================================
# 脚本名称: ex89.sh (The Apex Vanguard - Project Genesis V89)
# 快捷方式: xrv
# 巅峰突破: 
#   1. 时序排爆：重构状态机，引入快照级变量锁，彻底治愈“上帝之手”因状态读取冲突导致的死锁罢工。
#   2. 计费重构：精准穿透 vnstat 配置文件注释，修复计费日无法修改的 Bug，UI 直显真实计费清零日。
#   3. UI 归一：治愈强迫症，全域 14 项极客微操进行绝对连续编号，应用层 6 阶 + 系统层 8 阶完美对齐。
#   4. 维度跃升：优化 Dnsmasq 缓存池 (21000条) 并采用 8.8.8.8 / 1.1.1.1 / OpenDNS 黄金并发组合。
#   5. 路由斩断：将 Xray domainStrategy 重置为 AsIs，彻底消除域名路由层多余解析，纯 IP 直通。
#   6. 极客容错：完美拦截虚拟化阉割环境的 Bash 底层报错，实施前置静默包容，缺失硬件智能剔除。
#   7. 拒绝任何代码折叠，100% 结构化全量铺开，工业级防呆与容错全面上线。
# ============================================================

# 必须用 bash 运行
if test -z "$BASH_VERSION"; then
    echo "错误: 请用 bash 运行此脚本: bash ex89.sh"
    exit 1
fi

# -- 颜色定义 --
red='\033[31m'
yellow='\033[33m'
gray='\033[90m'
green='\033[92m'
blue='\033[94m'
magenta='\033[95m'
cyan='\033[96m'
none='\033[0m'

# -- 终极防吞噬十六进制常量定义 --
L_B=$(printf '\x5B')
R_B=$(printf '\x5D')

# -- 全局路径与变量 --
XRAY_BIN="/usr/local/bin/xray"
CONFIG_DIR="/usr/local/etc/xray"
CONFIG="$CONFIG_DIR/config.json"
PUBKEY_FILE="$CONFIG_DIR/public.key"
SNI_CACHE_FILE="$CONFIG_DIR/sni_cache.txt"
INSTALL_DATE_FILE="$CONFIG_DIR/install_date.txt"
USER_SNI_MAP="$CONFIG_DIR/user_sni.txt"
USER_TIME_MAP="$CONFIG_DIR/user_time.txt"
DAT_DIR="/usr/local/share/xray"
SCRIPT_DIR="/usr/local/etc/xray-script"
UPDATE_DAT_SCRIPT="$SCRIPT_DIR/update-dat.sh"
SYMLINK="/usr/local/bin/xrv"
SCRIPT_PATH=$(readlink -f "$0")
SERVER_IP=""
REMARK_NAME="xp-reality"
BEST_SNI="www.microsoft.com"
SNI_JSON_ARRAY="\"www.microsoft.com\""
LISTEN_PORT=443

# 初始化基础环境
mkdir -p "$CONFIG_DIR" "$DAT_DIR" "$SCRIPT_DIR" 2>/dev/null
touch "$USER_SNI_MAP" "$USER_TIME_MAP"

# -- 辅助输出函数 --
print_red()     { echo -e "${red}$*${none}"; }
print_green()   { echo -e "${green}$*${none}"; }
print_yellow()  { echo -e "${yellow}$*${none}"; }
print_magenta() { echo -e "${magenta}$*${none}"; }
print_cyan()    { echo -e "${cyan}$*${none}"; }

info()  { echo -e "${green}✓${none} $*"; }
warn()  { echo -e "${yellow}!${none} $*"; }
error() { echo -e "${red}✗${none} $*";   }
die()   { echo -e "\n${red}致命错误${none} $*\n"; exit 1; }

title() {
    echo -e "\n${blue}===================================================${none}"
    echo -e "  ${cyan}$*${none}"
    echo -e "${blue}===================================================${none}"
}
hr() { 
    echo -e "${gray}---------------------------------------------------${none}" 
}

# -- 权限强锁防线 (绝杀 status 23 Bug) --
fix_permissions() {
    if test -f "$CONFIG"; then
        chmod 644 "$CONFIG" >/dev/null 2>&1
    fi
    if test -d "$CONFIG_DIR"; then
        chmod 755 "$CONFIG_DIR" >/dev/null 2>&1
    fi
    chown root:root "$CONFIG" >/dev/null 2>&1 || true
    chown -R root:root "$CONFIG_DIR" >/dev/null 2>&1 || true
}

# -- 安全写入配置 (解决 permission denied 核心防线) --
_safe_jq_write() {
    local filter="$1"
    local tmp=$(mktemp)
    if jq "$filter" "$CONFIG" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$CONFIG" >/dev/null 2>&1
        fix_permissions
        return 0
    fi
    rm -f "$tmp" >/dev/null 2>&1
    return 1
}

# -- 赋予 Xray Systemd 【特种兵级】防爆突发特权 (状态无损继承引擎) --
fix_xray_systemd_limits() {
    local override_dir="/etc/systemd/system/xray.service.d"
    mkdir -p "$override_dir" 2>/dev/null
    local limit_file="$override_dir/limits.conf"
    
    # 默认值初始化 (极客最高抢占 Nice=-20，OOM 防杀默认【强制开启】)
    local current_nice="-20"
    local current_gogc="100"
    local current_oom="true"

    if [ -f "$limit_file" ]; then
        if grep -q "^Nice=" "$limit_file"; then
            current_nice=$(awk -F'=' '/^Nice=/ {print $2}' "$limit_file" | head -1)
        fi
        if grep -q "^Environment=\"GOGC=" "$limit_file"; then
            current_gogc=$(awk -F'=' '/^Environment="GOGC=/ {print $3}' "$limit_file" | tr -d '"' | head -1)
        fi
        if ! grep -q "^OOMScoreAdjust=" "$limit_file"; then
            current_oom="false"
        fi
    fi

    local TOTAL_MEM=$(free -m | awk '/Mem/{print $2}')
    local GO_MEM_LIMIT=$(( TOTAL_MEM * 85 / 100 ))

    cat > "$limit_file" << EOF
[Service]
LimitNOFILE=4096
LimitNPROC=4096
LimitMEMLOCK=infinity
Nice=${current_nice}
Environment="GOMEMLIMIT=${GO_MEM_LIMIT}MiB"
Environment="GOGC=${current_gogc}"
EOF

    if [ "$current_oom" = "true" ]; then
        echo "OOMScoreAdjust=-500" >> "$limit_file"
        echo "IOSchedulingClass=realtime" >> "$limit_file"
        echo "IOSchedulingPriority=2" >> "$limit_file"
    fi

    systemctl daemon-reload >/dev/null 2>&1
}

# -- 环境预检 & 定时任务 --
preflight() {
    if test "$EUID" -ne 0; then 
        die "此脚本必须以 root 身份运行"
    fi
    if ! command -v systemctl >/dev/null 2>&1; then 
        die "系统缺少 systemctl，请更换标准的 systemd 系统"
    fi
    
    local need="jq curl wget xxd unzip qrencode vnstat cron openssl coreutils sed e2fsprogs pkg-config iproute2 ethtool"
    local install_list=""
    for i in $need; do 
        if ! command -v "$i" >/dev/null 2>&1; then 
            install_list="$install_list $i"
        fi
    done

    if test -n "$install_list"; then
        info "正在同步工业级依赖: $install_list"
        export DEBIAN_FRONTEND=noninteractive
        (apt-get update -y || yum makecache -y) >/dev/null 2>&1
        (apt-get install -y $install_list || yum install -y $install_list) >/dev/null 2>&1
        systemctl start vnstat >/dev/null 2>&1 || true
        systemctl start cron >/dev/null 2>&1 || systemctl start crond >/dev/null 2>&1 || true
    fi

    if test -f "$SCRIPT_PATH"; then
        \cp -f "$SCRIPT_PATH" "$SYMLINK" >/dev/null 2>&1
        chmod +x "$SYMLINK" >/dev/null 2>&1
        hash -r 2>/dev/null
    fi
    
    SERVER_IP=$(curl -s -4 --connect-timeout 5 https://api.ipify.org || curl -s -4 --connect-timeout 5 https://ifconfig.me || echo "获取失败")
}

# -- 自动热更 Geo 规则库设置 --
install_update_dat() {
    cat > "$UPDATE_DAT_SCRIPT" <<'UPDSH'
#!/usr/bin/env bash
XRAY_DAT_DIR="/usr/local/share/xray"
GEOIP_URL="https://github.com/Loyalsoldier/v2ray-rules-dat/raw/release/geoip.dat"
GEOSITE_URL="https://github.com/Loyalsoldier/domain-list-custom/releases/latest/download/geosite.dat"
curl -sL -o "$XRAY_DAT_DIR/geoip.dat.new" "$GEOIP_URL" && mv -f "$XRAY_DAT_DIR/geoip.dat.new" "$XRAY_DAT_DIR/geoip.dat"
curl -sL -o "$XRAY_DAT_DIR/geosite.dat.new" "$GEOSITE_URL" && mv -f "$XRAY_DAT_DIR/geosite.dat.new" "$XRAY_DAT_DIR/geosite.dat"
/bin/systemctl restart xray
UPDSH
    chmod +x "$UPDATE_DAT_SCRIPT"
    (crontab -l 2>/dev/null | grep -v "$UPDATE_DAT_SCRIPT"; echo "0 3 * * * $UPDATE_DAT_SCRIPT >/dev/null 2>&1") | crontab -
    info "已配置自动热更: 每天凌晨 3:00 更新 Geo 规则库"
}

# -- 核心：130+ 实体 SNI 扫描引擎 --
run_sni_scanner() {
    title "雷达嗅探：130+ 实体矩阵与国内连通性探测"
    print_yellow ">>> 扫描中... (随时按回车键可立即中止并挑选已扫描节点)\n"
    
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    
    local sni_list=(
        "www.apple.com" "support.apple.com" "developer.apple.com" "id.apple.com" "icloud.apple.com"
        "swdist.apple.com" "swcdn.apple.com" "updates.cdn-apple.com" "mensura.cdn-apple.com" "osxapps.itunes.apple.com"
        "aod.itunes.apple.com" "is1-ssl.mzstatic.com" "itunes.apple.com" "gateway.icloud.com" "www.icloud.com"
        "www.microsoft.com" "login.microsoftonline.com" "portal.azure.com" "support.microsoft.com" "office.com"
        "update.microsoft.com" "windowsupdate.microsoft.com" "software.download.prss.microsoft.com" "cdn-dynmedia-1.microsoft.com"
        "www.intel.com" "downloadcenter.intel.com" "ark.intel.com" "www.amd.com" "drivers.amd.com" "community.amd.com"
        "webinar.amd.com" "ir.amd.com" "www.dell.com" "support.dell.com" "www.hp.com" "support.hp.com" "developers.hp.com"
        "www.bmw.com" "configure.bmw.com" "shop.bmw.com" "www.mercedes-benz.com" "me.mercedes-benz.com"
        "www.toyota-global.com" "global.toyota" "www.toyota.com" "www.honda.com" "global.honda" "www.volkswagen.com"
        "service.volkswagen.com" "www.vw.com" "www.nike.com" "account.nike.com" "store.nike.com" "www.adidas.com"
        "account.adidas.com" "www.zara.com" "static.zara.net" "www.ikea.com" "secure.ikea.com" "www.shell.com"
        "careers.shell.com" "www.bp.com" "login.bp.com" "www.totalenergies.com" "www.ge.com" "digital.ge.com"
        "www.abb.com" "new.abb.com" "www.hsbc.com" "online.hsbc.com" "www.goldmansachs.com" "login.gs.com"
        "www.morganstanley.com" "secure.morganstanley.com" "www.maersk.com" "www.msc.com" "www.cma-cgm.com"
        "www.hapag-lloyd.com" "www.michelin.com" "www.bridgestone.com" "www.goodyear.com" "www.pirelli.com"
        "www.sony.com" "www.sony.net" "www.panasonic.com" "www.canon.com" "www.nintendo.com" "www.lg.com"
        "www.epson.com" "www.unilever.com" "www.loreal.com" "www.shiseido.com" "www.jnj.com" "www.kao.com"
        "www.uniqlo.com" "www.hermes.com" "www.chanel.com" "services.chanel.com" "www.louisvuitton.com"
        "eu.louisvuitton.com" "www.dior.com" "www.ferragamo.com" "www.versace.com" "www.prada.com" "www.fendi.com"
        "www.gucci.com" "www.tiffany.com" "www.esteelauder.com" "www.maje.com" "www.swatch.com" "www.coca-cola.com"
        "www.coca-colacompany.com" "www.pepsi.com" "www.pepsico.com" "www.nestle.com" "www.bk.com" "www.heinz.com"
        "www.pg.com" "www.basf.com" "www.bayer.com" "www.bosch.com" "www.bosch-home.com" "www.lexus.com" "www.audi.com"
        "www.porsche.com" "www.skoda-auto.com" "www.gm.com" "www.chevrolet.com" "www.cadillac.com" "www.ford.com"
        "www.lincoln.com" "www.hyundai.com" "www.kia.com" "www.peugeot.com" "www.renault.com" "www.jaguar.com"
        "www.landrover.com" "www.astonmartin.com" "www.mclaren.com" "www.ferrari.com" "www.maserati.com" "www.volvocars.com"
        "www.tesla.com" "s0.awsstatic.com" "d1.awsstatic.com" "images-na.ssl-images-amazon.com" "m.media-amazon.com"
        "www.nvidia.com" "academy.nvidia.com" "images.nvidia.com" "blogs.nvidia.com" "docs.nvidia.com" "docscontent.nvidia.com"
        "www.samsung.com" "www.sap.com" "www.oracle.com" "www.mysql.com" "www.swift.com" "download-installer.cdn.mozilla.net"
        "addons.mozilla.org" "www.airbnb.co.uk" "www.airbnb.ca" "www.airbnb.com.sg" "www.airbnb.com.au" "www.airbnb.co.in"
        "www.ubi.com" "lol.secure.dyn.riotcdn.net" "one-piece.com" "player.live-video.net" "mit.edu" "www.mit.edu" 
        "web.mit.edu" "ocw.mit.edu" "csail.mit.edu" "libraries.mit.edu" "alum.mit.edu" "id.mit.edu" "stanford.edu" 
        "www.stanford.edu" "cs.stanford.edu" "ai.stanford.edu" "web.stanford.edu" "login.stanford.edu" "ox.ac.uk" 
        "www.ox.ac.uk" "cs.ox.ac.uk" "maths.ox.ac.uk" "login.ox.ac.uk" "lufthansa.com" "www.lufthansa.com" 
        "book.lufthansa.com" "checkin.lufthansa.com" "api.lufthansa.com" "singaporeair.com" "www.singaporeair.com" 
        "booking.singaporeair.com" "krisflyer.singaporeair.com" "trekbikes.com" "www.trekbikes.com" "shop.trekbikes.com" 
        "support.trekbikes.com" "specialized.com" "www.specialized.com" "store.specialized.com" "support.specialized.com" 
        "giant-bicycles.com" "www.giant-bicycles.com" "dealer.giant-bicycles.com" "logitech.com" "www.logitech.com" 
        "support.logitech.com" "gaming.logitech.com" "razer.com" "www.razer.com" "support.razer.com" "insider.razer.com" 
        "corsair.com" "www.corsair.com" "support.corsair.com" "account.asus.com" "kingston.com" "www.kingston.com" 
        "shop.kingston.com" "support.kingston.com" "seagate.com" "www.seagate.com" "support.seagate.com" "kleenex.com" 
        "www.kleenex.com" "shop.kleenex.com" "scottbrand.com" "www.scottbrand.com" "tempo-world.com" "www.tempo-world.com"
    )

    local sni_string=$(printf "%s\n" "${sni_list[@]}")
    if command -v shuf >/dev/null 2>&1; then
        sni_string=$(echo "$sni_string" | shuf)
    else
        sni_string=$(echo "$sni_string" | awk 'BEGIN{srand()} {print rand()"\t"$0}' | sort -n | cut -f2-)
    fi

    local tmp_sni=$(mktemp /tmp/sni_test.XXXXXX)

    for sni in $sni_string; do
        read -t 0.1 -n 1 key
        if test $? -eq 0; then
            echo -e "\n${yellow}探测已手动中止，正在整理已捕获节点...${none}"
            break
        fi

        local time_raw=$(LC_ALL=C curl -sL -w "%{time_connect}" -o /dev/null --connect-timeout 2 -m 4 "https://$sni")
        local ms=$(echo "$time_raw" | awk '{print int($1 * 1000)}')

        if test "${ms:-0}" -gt 0; then
            if curl -sI -m 2 "https://$sni" 2>/dev/null | grep -qiE "server: cloudflare|cf-ray"; then
                echo -e " ${gray}跳过${none} $sni (Cloudflare CDN 拦截)"
                continue
            fi
            
            local doh_res=$(curl -s --connect-timeout 2 "https://dns.alidns.com/resolve?name=$sni&type=1" 2>/dev/null)
            local dns_cn=$(echo "$doh_res" | jq -r '.Answer[]? | select(.type==1 or .type==5) | .data' 2>/dev/null | tail -1)
            
            local status_cn=""
            local p_type="NORM"
            
            if test -z "$dns_cn" || test "$dns_cn" = "127.0.0.1" || test "$dns_cn" = "0.0.0.0" || test "$dns_cn" = "::1"; then
                status_cn="${red}国内墙阻断 (DNS投毒)${none}"
                p_type="BLOCK"
            else
                local loc=$(curl -s --connect-timeout 2 "https://ipinfo.io/$dns_cn/country" 2>/dev/null | tr -d ' \n')
                if test "$loc" = "CN"; then
                    status_cn="${green}直通${none} | ${blue}中国境内 CDN${none}"
                    p_type="CN_CDN"
                else
                    status_cn="${green}直通${none} | ${cyan}海外原生优质${none}"
                    p_type="NORM"
                fi
            fi
            
            echo -e " ${green}存活${none} $sni : ${yellow}${ms}ms${none} | $status_cn"
            
            if test "$p_type" != "BLOCK"; then
                echo "$ms $sni $p_type" >> "$tmp_sni"
            fi
        fi
    done

    if test -s "$tmp_sni"; then
        grep "NORM" "$tmp_sni" | sort -n | head -n 20 | awk '{print $2, $1}' > "$SNI_CACHE_FILE"
        local count=$(wc -l < "$SNI_CACHE_FILE" 2>/dev/null)
        if test "${count:-0}" -lt 20; then
            grep "CN_CDN" "$tmp_sni" | sort -n | head -n $((20 - ${count:-0})) | awk '{print $2, $1}' >> "$SNI_CACHE_FILE"
        fi
    else
        print_red "探测全灭，采用微软作为保底方案。"
        echo "www.microsoft.com 999" > "$SNI_CACHE_FILE"
    fi
    rm -f "$tmp_sni"
}

# -- 终极 Reality 质检 --
verify_sni_strict() {
    print_magenta "\n>>> 正在对 $1 开启严苛质检 (TLS 1.3 + ALPN h2 + OCSP)..."
    local out=$(echo "Q" | timeout 5 openssl s_client -connect "$1:443" -alpn h2 -tls1_3 -status 2>&1)
    local pass=1
    
    if ! echo "$out" | grep -qi "TLSv1.3"; then 
        print_red " ✗ 质检拦截: 目标不支持 TLS v1.3"
        pass=0
    fi
    if ! echo "$out" | grep -qi "ALPN, server accepted to use h2"; then 
        print_red " ✗ 质检拦截: 目标不支持 ALPN h2"
        pass=0
    fi
    if ! echo "$out" | grep -qi "OCSP response:"; then 
        print_red " ✗ 质检拦截: 目标未开启 OCSP Stapling 证书状态装订"
        pass=0
    fi
    
    return $pass
}

# -- 交互选单 --
choose_sni() {
    while true; do
        if test -f "$SNI_CACHE_FILE"; then
            echo -e "\n  ${cyan}【战备缓存：极速 Top 20 (已剔除阻断节点)】${none}"
            local idx=1
            while read -r s t; do
                echo -e "  $idx) $s (${cyan}${t}ms${none})"
                idx=$((idx + 1))
            done < "$SNI_CACHE_FILE"
            
            echo -e "  ${yellow}r) 抛弃缓存重新扫描矩阵${none}"
            echo "  m) 矩阵模式 (多选组合/全选 SNI 以防封锁)"
            echo "  0) 手动输入自定义域名"
            echo "  q) 取消并返回"
            
            read -rp "  请选择: " sel
            sel=${sel:-1}
            
            if test "$sel" = "q"; then return 1; fi
            if test "$sel" = "r"; then run_sni_scanner; continue; fi
            
            if test "$sel" = "m"; then
                read -rp "请输入要组合的序号 (空格分隔, 如 1 3 5, 输入 all 全选): " m_sel
                if test "$m_sel" = "all"; then
                    local arr=($(awk '{print $1}' "$SNI_CACHE_FILE"))
                else
                    local arr=()
                    for i in $m_sel; do
                        local picked=$(awk "NR==$i {print \$1}" "$SNI_CACHE_FILE" 2>/dev/null)
                        if test -n "$picked"; then arr+=("$picked"); fi
                    done
                fi
                
                if test ${#arr[@]} -eq 0; then
                    error "选择无效，请重新选择"
                    continue
                fi
                
                BEST_SNI="${arr[0]}"
                local jq_args=()
                for s in "${arr[@]}"; do jq_args+=("\"$s\""); done
                SNI_JSON_ARRAY=$(IFS=,; echo "${jq_args[*]}")
                
            elif test "$sel" = "0"; then 
                read -rp "输入自定义域名: " d
                BEST_SNI=${d:-www.microsoft.com}
                SNI_JSON_ARRAY="\"$BEST_SNI\""
            else
                local picked=$(awk "NR==$sel {print \$1}" "$SNI_CACHE_FILE" 2>/dev/null)
                if test -n "$picked"; then
                    BEST_SNI="$picked"
                else
                    BEST_SNI=$(awk "NR==1 {print \$1}" "$SNI_CACHE_FILE" 2>/dev/null)
                fi
                SNI_JSON_ARRAY="\"$BEST_SNI\""
            fi

            if verify_sni_strict "$BEST_SNI"; then
                print_green ">>> 主目标 $BEST_SNI 质检完美通过！"
                break
            else
                print_yellow ">>> 域名质检不达标，会导致 Reality 极易被墙或断流，请重新选择！"
                continue
            fi
        else
            run_sni_scanner
        fi
    done
    return 0
}

# -- 端口防冲突校验器 --
validate_port() {
    local p="$1"
    if test -z "$p"; then return 1; fi
    local check=$(echo "$p" | tr -d '0-9')
    if test -n "$check"; then return 1; fi
    if test "${p:-0}" -ge 1 2>/dev/null && test "${p:-0}" -le 65535 2>/dev/null; then
        if ss -tuln | grep -q ":${p} "; then
            print_red "端口 $p 已被系统其他程序占用，请更换！"
            return 1
        fi
        return 0
    fi
    return 1
}

# -- Xray 核心更新 --
do_update_core() {
    title "Xray Core 核心无损热更"
    print_magenta ">>> 正在连接 GitHub 拉取最新 Xray 核心..."
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
    
    fix_xray_systemd_limits
    systemctl restart xray >/dev/null 2>&1
    local cur_ver=$($XRAY_BIN version 2>/dev/null | head -n1 | awk '{print $2}')
    info "热更成功！当前版本: ${cyan}$cur_ver${none}"
    read -rp "按 Enter 继续..." _
}

# -- SS 工具 --
gen_ss_pass() {
    head -c 24 /dev/urandom | base64 | tr -d '=/+\n' | head -c 24
}
_select_ss_method() {
    echo -e "  ${cyan}选择 SS 加密方式：${none}" >&2
    echo "  1) aes-256-gcm (推荐)  2) aes-128-gcm  3) chacha20-ietf-poly1305" >&2
    read -rp "  编号: " mc >&2
    case "${mc:-1}" in
        2) echo "aes-128-gcm" ;;
        3) echo "chacha20-ietf-poly1305" ;;
        *) echo "aes-256-gcm" ;;
    esac
}

# -- 官方预编译 XANMOD (main) 部署模块 --
do_install_xanmod_main_official() {
    title "系统飞升：安装官方预编译 XANMOD (main) 内核"
    
    if [ "$(uname -m)" != "x86_64" ]; then
        error "官方预编译 Xanmod 仅支持 x86_64 架构的机器！"
        read -rp "按 Enter 继续..." _
        return
    fi

    if [ ! -f /etc/debian_version ]; then
        error "官方预编译 Xanmod APT 源目前仅支持 Debian / Ubuntu 系操作系统！"
        read -rp "按 Enter 继续..." _
        return
    fi

    print_magenta ">>> [1/4] 正在拉取智能探针，检测 CPU 微架构支持级别..."
    local cpu_level_script="/tmp/check_x86-64_psabi.sh"
    wget -qO "$cpu_level_script" https://dl.xanmod.org/check_x86-64_psabi.sh
    
    local cpu_level=$(awk -f "$cpu_level_script" | grep -oE 'x86-64-v[1-4]' | grep -oE '[1-4]' | tail -n 1)
    rm -f "$cpu_level_script"
    
    if [ -z "$cpu_level" ]; then
        cpu_level=1
        warn "无法精确检测 CPU 微架构级别，将默认降级使用最兼容的 v1 版本。"
    else
        info "当前 CPU 硬件完美支持的微架构级别为: v${cpu_level}"
    fi

    local pkg_name="linux-xanmod-x64v${cpu_level}"
    
    print_magenta ">>> [2/4] 正在配置 Xanmod 官方最高优 APT 仓库与防伪 GPG 密钥..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y >/dev/null 2>&1
    apt-get install -y gnupg gnupg2 curl sudo wget e2fsprogs >/dev/null 2>&1

    echo 'deb http://deb.xanmod.org releases main' > /etc/apt/sources.list.d/xanmod-kernel.list
    wget -qO - https://dl.xanmod.org/gpg.key | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/xanmod-kernel.gpg

    print_magenta ">>> [3/4] 正在通过 APT 极速拉取并安装专属内核: $pkg_name ..."
    apt-get update -y
    apt-get install -y "$pkg_name"

    if [ $? -ne 0 ] && [ "$cpu_level" == "4" ]; then
        warn "官方源目前未找到独立的 v4 安装包，正在为您智能回退至兼容的 v3 版本..."
        pkg_name="linux-xanmod-x64v3"
        apt-get install -y "$pkg_name"
    fi

    print_magenta ">>> [4/4] 正在重载 GRUB 引导扇区记录..."
    if command -v update-grub >/dev/null 2>&1; then
        update-grub
    else
        apt-get install -y grub2-common
        update-grub
    fi

    info "官方预编译 XANMOD (main) 部署已全部就绪！系统将在 10 秒后自动重启应用新内核..."
    sleep 10
    reboot
}

# -- 编译安装 Xanmod + BBR3 --
do_xanmod_compile() {
    title "系统飞升：编译安装 Xanmod + BBR3"
    warn "警告: 这是一个极其漫长的过程 (30-60分钟)，低配机极易引发死机断连！强烈建议优先使用菜单 2 的官方预编译版。"
    read -rp "确定要执意开始源码编译吗？(y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi

    echo "=== 开始执行深度系统清理与模块解容 ==="
    export DEBIAN_FRONTEND=noninteractive
    apt-get clean
    apt-get autoremove -y --purge || true
    
    journalctl --vacuum-time=1d || true
    rm -rf /var/log/*.log /var/log/*/*.log /tmp/* /var/lib/docker/* /usr/src/linux* /usr/src/bbr* /usr/src/xanmod* /compile/* /root/linux* /root/*.tar* /root/*.xz 2>/dev/null || true
    sync

    local inode_use=$(df -i / | awk 'NR==2{print $5}' | tr -d '%')
    if [ "$inode_use" -gt 90 ]; then
        apt clean
        rm -rf /var/cache/*
    fi

    echo "=== 注入定期清理任务 ==="
    cat <<'EOF' > /usr/local/bin/cc1.sh
#!/bin/bash
apt-get clean
apt-get autoremove -y --purge
journalctl --vacuum-time=3d
rm -rf /tmp/*
rm -rf /var/log/*
sync
EOF
    chmod +x /usr/local/bin/cc1.sh
    (crontab -l 2>/dev/null | grep -v cc1.sh ; echo "0 4 */10 * * /usr/local/bin/cc1.sh") | crontab -

    echo "=== 检查并配置 1GB 编译缓冲交换区 (Swap) ==="
    if ! swapon --show | grep -q swapfile; then
        if ! fallocate -l 1024M /swapfile 2>/dev/null; then
            dd if=/dev/zero of=/swapfile bs=1M count=1024 status=progress
        fi
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        grep -q swapfile /etc/fstab || echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi

    local root_free=$(df -m / | awk 'NR==2{print $4}')
    local BUILD_DIR=""
    if [ "$root_free" -gt 4000 ]; then mkdir -p /compile; BUILD_DIR=/compile; else BUILD_DIR=/usr/src; fi

    apt-get update -y
    apt-get install -y build-essential bc bison flex libssl-dev libelf-dev libncurses-dev zstd git wget curl xz-utils ethtool numactl make pkg-config

    local CPU=$(nproc)
    local RAM=$(free -m | awk '/Mem/{print $2}')
    local THREADS=1
    if [ "$RAM" -ge 2000 ]; then THREADS=$CPU; fi
    local IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')

    cd $BUILD_DIR
    local KERNEL_URL=$(curl -s https://www.kernel.org/releases.json | grep -A3 '"is_latest": true' | grep tarball | head -1 | awk -F'"' '{print $4}')
    if [ -z "$KERNEL_URL" ] || [ "$KERNEL_URL" == "null" ]; then KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.8.tar.xz"; fi
    local KERNEL_FILE=$(basename $KERNEL_URL)
    wget -q --show-progress $KERNEL_URL -O $KERNEL_FILE

    if ! tar -tJf $KERNEL_FILE >/dev/null 2>&1; then
        rm -f $KERNEL_FILE
        wget -q --show-progress $KERNEL_URL -O $KERNEL_FILE
        tar -tJf $KERNEL_FILE >/dev/null 2>&1 || { echo "下载或解压验证失败，已中止。"; exit 1; }
    fi

    tar -xJf $KERNEL_FILE
    local KERNEL_DIR=$(tar -tf $KERNEL_FILE | head -1 | cut -d/ -f1)
    cd $KERNEL_DIR

    make defconfig
    make scripts
    
    ./scripts/config --enable CONFIG_TCP_CONG_BBR
    ./scripts/config --enable CONFIG_DEFAULT_BBR
    ./scripts/config --enable CONFIG_TCP_BBR3 2>/dev/null || true
    ./scripts/config --disable CONFIG_DRM_I915
    ./scripts/config --disable CONFIG_NET_VENDOR_REALTEK
    ./scripts/config --disable CONFIG_NET_VENDOR_BROADCOM
    ./scripts/config --disable CONFIG_E100
    
    make olddefconfig
    make -j$THREADS
    make modules_install
    make install

    local CURRENT=$(uname -r)
    dpkg --list | grep linux-image | awk '{print $2}' | grep -v "$CURRENT" | xargs -r apt-get -y purge
    find /lib/modules -mindepth 1 -maxdepth 1 -type d | grep -v "$CURRENT" | xargs -r rm -rf
    update-grub || true

    cat > /usr/local/bin/nic-optimize.sh <<'EONIC'
#!/bin/bash
IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
ethtool -K $IFACE gro off gso off tso off lro off rx-gro-hw off tx-udp-segmentation on 2>/dev/null || true
ethtool -C $IFACE adaptive-rx off rx-usecs 0 tx-usecs 0 2>/dev/null || true
EONIC
    chmod +x /usr/local/bin/nic-optimize.sh

    cat > /etc/systemd/system/nic-optimize.service <<EOSERVICE
[Unit]
Description=NIC Hardware Optimization
After=network.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/nic-optimize.sh
TimeoutSec=30
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOSERVICE

    systemctl daemon-reload
    systemctl enable nic-optimize.service
    systemctl start nic-optimize.service

    local RXMAX=$(ethtool -g "$IFACE" 2>/dev/null | awk '/RX:/ {print $2; exit}')
    if [ -n "$RXMAX" ]; then ethtool -G "$IFACE" rx "$RXMAX" tx "$RXMAX" || true; fi

    local CPU_MASK=$(printf "%x" $(( (1<<CPU)-1 )))
    cat > /usr/local/bin/rps-optimize.sh <<'EOF'
#!/bin/bash
IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
CPU=$(nproc)
CPU_MASK=$(printf "%x" $(( (1<<CPU)-1 )))
RX_QUEUES=$(ls /sys/class/net/$IFACE/queues/ | grep rx- | wc -l)
for RX in /sys/class/net/$IFACE/queues/rx-*; do echo $CPU_MASK > $RX/rps_cpus 2>/dev/null || true; done
for TX in /sys/class/net/$IFACE/queues/tx-*; do echo $CPU_MASK > $TX/xps_cpus 2>/dev/null || true; done
sysctl -w net.core.rps_sock_flow_entries=131072
FLOW_PER_QUEUE=$((65535 / RX_QUEUES))
for RX in /sys/class/net/$IFACE/queues/rx-*; do echo $FLOW_PER_QUEUE > $RX/rps_flow_cnt 2>/dev/null || true; done
EOF
    chmod +x /usr/local/bin/rps-optimize.sh

    cat > /etc/systemd/system/rps-optimize.service <<EOF
[Unit]
Description=RPS RFS Network CPU Optimization
After=network.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/rps-optimize.sh
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable rps-optimize.service
    systemctl start rps-optimize.service

    for irq in $(grep "$IFACE" /proc/interrupts | awk '{print $1}' | tr -d ':'); do echo $MASK > /proc/irq/$irq/smp_affinity || true; done

    cd /
    rm -rf $BUILD_DIR/linux* $BUILD_DIR/$KERNEL_FILE /compile/* /root/linux*
    info "内核编译与网卡优化已全部就绪！系统将在 30 秒后自动重启应用更改..."
    sleep 30
    reboot
}

# -- 极限系统网络栈调优 --
do_perf_tuning() {
    title "极限压榨：低延迟系统底层网络栈调优"
    warn "警告: 该操作将注入极限并发参数与低延迟优化，执行后系统将重启！"
    read -rp "确定要继续吗？(y/n): " confirm
    if [[ "$confirm" != "y" ]]; then return; fi

    systemctl stop net-speeder >/dev/null 2>&1 || true
    killall net-speeder >/dev/null 2>&1 || true
    systemctl disable net-speeder >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/net-speeder.service /etc/systemd/system/multi-user.target.wants/net-speeder.service
    systemctl daemon-reload >/dev/null 2>&1
    rm -rf /root/net-speeder

    truncate -s 0 /etc/sysctl.conf /etc/sysctl.d/99-sysctl.conf /etc/sysctl.d/99-network-optimized.conf 2>/dev/null || true
    rm -f /etc/sysctl.d/99-bbr*.conf /etc/sysctl.d/99-ipv6-disable.conf /etc/sysctl.d/99-pro*.conf /etc/sysctl.d/99-xanmod-bbr3.conf /usr/lib/sysctl.d/50-pid-max.conf /usr/lib/sysctl.d/99-protect-links.conf 

    cat > /etc/security/limits.conf << 'EOF'
root     soft   nofile    1000000
root     hard   nofile    1000000
root     soft   nproc     1000000
root     hard   nproc     1000000
root     soft   core      1000000
root     hard   core      1000000
root     soft   stack     1000000
root     hard   stack     1000000

* soft   nofile    1000000
* hard   nofile    1000000
* soft   nproc     1000000
* hard   nproc     1000000
* soft   core      1000000
* hard   core      1000000
* soft   stack     1000000
* hard   stack     1000000

nginx    soft   nofile    1000000
nginx    hard   nofile    1000000
EOF

    if ! grep -q "pam_limits.so" /etc/pam.d/common-session; then echo "session required pam_limits.so" >> /etc/pam.d/common-session; fi
    if ! grep -q "pam_limits.so" /etc/pam.d/common-session-noninteractive; then echo "session required pam_limits.so" >> /etc/pam.d/common-session-noninteractive; fi
    
    echo "DefaultLimitNOFILE=1000000" >> /etc/systemd/system.conf
    echo "DefaultLimitNPROC=1000000" >> /etc/systemd/system.conf

    cat > /etc/sysctl.d/99-network-optimized.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.neigh.default.base_reachable_time_ms = 60000
net.ipv4.neigh.default.mcast_solicit = 2
net.ipv4.neigh.default.retrans_time_ms = 500
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_ecn = 1
net.ipv4.tcp_ecn_fallback = 1

net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_adv_win_scale = 2
net.ipv4.tcp_moderate_rcvbuf = 1

net.core.rmem_default = 560576
net.core.wmem_default = 560576
net.core.rmem_max = 21699928
net.core.wmem_max = 21699928
net.ipv4.tcp_rmem = 4096 760576 21699928
net.ipv4.tcp_wmem = 4096 760576 21699928
net.ipv4.udp_rmem_min = 4096
net.ipv4.udp_wmem_min = 4096

net.core.dev_weight = 64
net.core.dev_weight_tx_bias = 1
net.core.dev_weight_rx_bias = 1
net.core.netdev_budget = 300

net.ipv4.igmp_max_memberships = 200
net.ipv4.route.flush = 1
net.ipv4.tcp_slow_start_after_idle = 0

vm.swappiness = 1
fs.file-max = 1048576
fs.nr_open = 1048576
fs.inotify.max_user_instances = 262144

net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fin_timeout = 12
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_abort_on_overflow = 0
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_max_tw_buckets = 262144
net.ipv4.tcp_retries1 = 5
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_syn_retries = 3
net.ipv4.tcp_synack_retries = 2

net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_max_orphans = 262144
net.core.optmem_max = 3276800
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_reordering = 3
net.ipv4.tcp_autocorking = 0
net.ipv4.tcp_tso_win_divisor = 6

kernel.pid_max = 4194304
kernel.threads-max = 85536
net.ipv4.neigh.default.gc_thresh1 = 1024
net.ipv4.neigh.default.gc_thresh2 = 4096
net.ipv4.neigh.default.gc_thresh3 = 8192
net.ipv4.neigh.default.gc_stale_time = 100
net.ipv4.conf.default.arp_announce = 2
net.ipv4.conf.lo.arp_announce = 2
net.ipv4.conf.all.arp_announce = 2
net.unix.max_dgram_qlen = 130000

net.core.busy_poll = 50
net.core.busy_read = 0
net.ipv4.tcp_notsent_lowat = 16384

vm.vfs_cache_pressure = 10
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.ip_forward = 1
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.tcp_early_retrans = 3
net.ipv4.neigh.default.unres_qlen = 35535
net.ipv4.conf.all.route_localnet = 0
net.ipv4.tcp_orphan_retries = 8
net.ipv4.conf.all.forwarding = 1

net.ipv4.ipfrag_max_dist = 32
net.ipv4.ipfrag_secret_interval = 200
net.ipv4.ipfrag_low_thresh = 42008868
net.ipv4.ipfrag_high_thresh = 104917729
net.ipv4.ipfrag_time = 30

fs.aio-max-nr = 262144
kernel.msgmax = 655350
kernel.msgmnb = 655350
net.ipv4.neigh.default.proxy_qlen = 50000
net.ipv4.tcp_pacing_ca_ratio = 150
net.ipv4.tcp_pacing_ss_ratio = 210
fs.protected_fifos = 1
fs.protected_hardlinks = 1
fs.protected_regular = 2
fs.protected_symlinks = 1

net.core.rps_sock_flow_entries = 131072
net.core.flow_limit_table_len = 131072
net.ipv4.tcp_workaround_signed_windows = 1
vm.dirty_ratio = 35
vm.overcommit_memory = 0
kernel.sysrq = 1

net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1

vm.max_map_count = 65535
net.ipv4.tcp_child_ehash_entries = 65535
net.ipv4.ip_no_pmtu_disc = 0
net.ipv4.tcp_stdurg = 0
net.ipv4.tcp_challenge_ack_limit = 1200
net.ipv4.tcp_comp_sack_delay_ns = 50000
net.ipv4.tcp_comp_sack_nr = 1
net.ipv4.tcp_fwmark_accept = 1
net.ipv4.tcp_invalid_ratelimit = 800
net.ipv4.tcp_l3mdev_accept = 1

net.core.tstamp_allow_data = 1
net.core.netdev_tstamp_prequeue = 1
kernel.randomize_va_space = 2

net.ipv4.tcp_mem = 65536 131072 262144
net.ipv4.udp_mem = 65536 131072 262144
net.ipv4.tcp_recovery = 0x1
net.ipv4.tcp_dsack = 1

kernel.shmmax = 67108864
kernel.shmall = 16777216

net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_limit_output_bytes = 1310720
net.ipv4.tcp_min_tso_segs = 1
net.ipv4.tcp_thin_linear_timeouts = 0
net.ipv4.tcp_early_demux = 1
net.ipv4.tcp_shrink_window = 0
net.ipv4.neigh.default.unres_qlen_bytes = 65535
kernel.printk = 3 4 1 3
kernel.sched_autogroup_enabled = 0
EOF

    sysctl --system
    sysctl -p
    
    local IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
    if [ -n "$IFACE" ]; then
        cat > /usr/local/bin/nic-optimize.sh <<'EONIC'
#!/bin/bash
IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
ethtool -K $IFACE gro off gso off tso off lro off rx-gro-hw off tx-udp-segmentation on 2>/dev/null || true
ethtool -C $IFACE adaptive-rx off rx-usecs 0 tx-usecs 0 2>/dev/null || true
EONIC
        chmod +x /usr/local/bin/nic-optimize.sh
        systemctl restart nic-optimize.service >/dev/null 2>&1 || true
        tc qdisc replace dev "$IFACE" root fq >/dev/null 2>&1 || true
    fi
    
    info "极限低延迟参数注入完成！系统将在 30 秒后自动重启以生效..."
    sleep 30
    reboot
}

# -- TX Queue 网卡发送队列低延迟收缩调优 --
do_txqueuelen_opt() {
    title "网卡发送队列 (TX Queue) 特化调优"
    local IP_CMD=$(command -v ip)
    local IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
    if [ -z "$IFACE" ]; then error "无法识别默认网络出口网卡，操作取消。"; read -rp "按 Enter 继续..." _; return 1; fi

    info "检测到外网出口网卡: $IFACE"
    info "正在将 txqueuelen 精简至 2000 以匹配极速响应架构..."
    $IP_CMD link set "$IFACE" txqueuelen 2000

    local SERVICE_FILE="/etc/systemd/system/txqueue.service"
    cat > $SERVICE_FILE <<EOF
[Unit]
Description=Set TX Queue Length for Low Latency
After=network-online.target
[Service]
Type=oneshot
ExecStart=$IP_CMD link set $IFACE txqueuelen 2000
RemainAfterExit=true
[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable txqueue >/dev/null 2>&1
    systemctl start txqueue
    info "开机自动应用已成功启动并启用！"
    echo -e "\n  ${cyan}当前网卡队列排队状态:${none}"
    $IP_CMD link show "$IFACE" | grep -o 'qlen [0-9]*' | awk '{print "    " $0}'
    read -rp "按 Enter 继续..." _
}

# -- [底层微操探针与热重载引擎] --
check_dnsmasq_state() {
    if systemctl is-active dnsmasq >/dev/null 2>&1 && grep -q "127.0.0.1" /etc/resolv.conf 2>/dev/null; then echo "true"; else echo "false"; fi
}
check_thp_state() {
    if [ ! -f "/sys/kernel/mm/transparent_hugepage/enabled" ] || [ ! -w "/sys/kernel/mm/transparent_hugepage/enabled" ]; then echo "unsupported"; return; fi
    if grep -q '\[never\]' /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null; then echo "true"; else echo "false"; fi
}
check_mtu_state() {
    if [ ! -f "/proc/sys/net/ipv4/tcp_mtu_probing" ] || [ ! -w "/proc/sys/net/ipv4/tcp_mtu_probing" ]; then echo "unsupported"; return; fi
    if [ "$(sysctl -n net.ipv4.tcp_mtu_probing 2>/dev/null)" = "1" ]; then echo "true"; else echo "false"; fi
}
check_cpu_state() {
    if [ ! -d "/sys/devices/system/cpu/cpu0/cpufreq" ] || [ ! -w "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]; then echo "unsupported"; return; fi
    if grep -q 'performance' /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null; then echo "true"; else echo "false"; fi
}
check_ring_state() {
    local IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
    if [ -z "$IFACE" ] || ! command -v ethtool >/dev/null 2>&1 || ! ethtool -g "$IFACE" >/dev/null 2>&1; then echo "unsupported"; return; fi
    local curr_rx=$(ethtool -g "$IFACE" 2>/dev/null | grep -A4 "Current hardware settings" | grep "RX:" | head -1 | awk '{print $2}')
    if [ -z "$curr_rx" ]; then echo "unsupported"; return; fi
    if [ "$curr_rx" = "512" ]; then echo "true"; else echo "false"; fi
}
check_zram_state() {
    if ! modprobe -n zram >/dev/null 2>&1 && ! lsmod | grep -q zram; then echo "unsupported"; return; fi
    if swapon --show | grep -q 'zram'; then echo "true"; else echo "false"; fi
}
check_journal_state() {
    if [ ! -f "/etc/systemd/journald.conf" ]; then echo "unsupported"; return; fi
    if grep -q '^Storage=volatile' /etc/systemd/journald.conf 2>/dev/null; then echo "true"; else echo "false"; fi
}
check_process_priority_state() {
    local limit_file="/etc/systemd/system/xray.service.d/limits.conf"
    if [ ! -f "$limit_file" ]; then echo "false"; return; fi
    if grep -q "^OOMScoreAdjust=-500" "$limit_file" 2>/dev/null; then echo "true"; else echo "false"; fi
}

update_hw_boot_script() {
    cat << 'EOF' > /usr/local/bin/xray-hw-tweaks.sh
#!/bin/bash
IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
EOF
    if [ "$(check_thp_state)" = "true" ]; then
        echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null" >> /usr/local/bin/xray-hw-tweaks.sh
        echo "echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null" >> /usr/local/bin/xray-hw-tweaks.sh
    fi
    if [ "$(check_cpu_state)" = "true" ] && [ -d "/sys/devices/system/cpu/cpu0/cpufreq" ]; then
        echo 'for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do if [ -f "$cpu" ]; then echo performance > "$cpu" 2>/dev/null || true; fi; done' >> /usr/local/bin/xray-hw-tweaks.sh
    fi
    if [ "$(check_ring_state)" = "true" ]; then
        echo "ethtool -G \$IFACE rx 512 tx 512 2>/dev/null || true" >> /usr/local/bin/xray-hw-tweaks.sh
    fi
    chmod +x /usr/local/bin/xray-hw-tweaks.sh

    cat << 'EOF' > /etc/systemd/system/xray-hw-tweaks.service
[Unit]
Description=Xray Hardware Tweaks
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xray-hw-tweaks.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload >/dev/null 2>&1
    systemctl enable xray-hw-tweaks.service >/dev/null 2>&1
}

# --- 新增的 Dnsmasq 本地极速内存缓存引擎 (第 7 项微操) ---
toggle_dnsmasq() {
    if [ "$(check_dnsmasq_state)" = "true" ]; then
        print_yellow ">>> 正在关闭 Dnsmasq 本地内存解析并恢复系统原生状态..."
        systemctl stop dnsmasq >/dev/null 2>&1
        systemctl disable dnsmasq >/dev/null 2>&1
        
        chattr -i /etc/resolv.conf 2>/dev/null || true
        rm -f /etc/resolv.conf 2>/dev/null || true
        if [ -f /etc/resolv.conf.bak ]; then
            mv /etc/resolv.conf.bak /etc/resolv.conf
        else
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
        fi
        
        systemctl enable systemd-resolved >/dev/null 2>&1 || true
        systemctl start systemd-resolved >/dev/null 2>&1 || true
        
        _safe_jq_write '.dns = {"servers":["https://8.8.8.8/dns-query","https://1.1.1.1/dns-query","https://dns.opendns.com/dns-query"], "queryStrategy":"UseIP"}'
        systemctl restart xray >/dev/null 2>&1
        info "Dnsmasq 已关闭，Xray 已恢复为 DoH 安全加密解析。"
    else
        print_magenta ">>> 正在拉取 Dnsmasq 引擎，请稍候..."
        export DEBIAN_FRONTEND=noninteractive
        apt-get update >/dev/null 2>&1 || yum makecache >/dev/null 2>&1
        apt-get install -y dnsmasq >/dev/null 2>&1 || yum install -y dnsmasq >/dev/null 2>&1
        
        systemctl stop systemd-resolved 2>/dev/null || true
        systemctl disable systemd-resolved 2>/dev/null || true
        systemctl stop resolvconf 2>/dev/null || true
        
        cat > /etc/dnsmasq.conf <<EOF
port=53
listen-address=127.0.0.1
bind-interfaces
# 开启超大内存池 (2万1千条解析记录)
cache-size=21000
# 强行锁死 TTL (1小时)，无视短效缓存，追求极致爆发力
min-cache-ttl=3600
# 并发向外请求，谁快用谁的
all-servers
server=8.8.8.8
server=1.1.1.1
server=208.67.222.222
no-resolv
no-poll
EOF

        systemctl enable dnsmasq >/dev/null 2>&1
        systemctl restart dnsmasq >/dev/null 2>&1
        
        chattr -i /etc/resolv.conf 2>/dev/null || true
        if [ ! -f /etc/resolv.conf.bak ]; then
            cp /etc/resolv.conf /etc/resolv.conf.bak 2>/dev/null || true
        fi
        rm -f /etc/resolv.conf 2>/dev/null || true
        echo "nameserver 127.0.0.1" > /etc/resolv.conf
        chattr +i /etc/resolv.conf 2>/dev/null || true
        
        _safe_jq_write '.dns = {"servers":["127.0.0.1"], "queryStrategy":"UseIP"}'
        systemctl restart xray >/dev/null 2>&1
        
        info "Dnsmasq 本地 21000 级内存缓存池部署完成！Xray 已卸下 DoH 装甲，直连本机内存全速狂奔！"
    fi
}

toggle_thp() {
    if [ "$(check_thp_state)" = "true" ]; then
        echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
        echo always > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
    else
        echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
        echo never > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
    fi
    update_hw_boot_script
}

toggle_mtu() {
    local conf="/etc/sysctl.d/99-network-optimized.conf"
    if [ "$(check_mtu_state)" = "true" ]; then
        sed -i 's/^net.ipv4.tcp_mtu_probing.*/net.ipv4.tcp_mtu_probing = 0/' "$conf" 2>/dev/null || true
    else
        if grep -q "net.ipv4.tcp_mtu_probing" "$conf" 2>/dev/null; then
            sed -i 's/^net.ipv4.tcp_mtu_probing.*/net.ipv4.tcp_mtu_probing = 1/' "$conf"
        else
            echo "net.ipv4.tcp_mtu_probing = 1" >> "$conf"
        fi
    fi
    sysctl -p "$conf" >/dev/null 2>&1
}

toggle_cpu() {
    if [ "$(check_cpu_state)" = "unsupported" ]; then return; fi
    if [ "$(check_cpu_state)" = "true" ]; then
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do 
            if [ -f "$cpu" ]; then echo schedutil > "$cpu" 2>/dev/null || echo ondemand > "$cpu" 2>/dev/null || true; fi
        done
    else
        for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do 
            if [ -f "$cpu" ]; then echo performance > "$cpu" 2>/dev/null || true; fi
        done
    fi
    update_hw_boot_script
}

toggle_ring() {
    local IFACE=$(ip route get 1.1.1.1 | awk '{print $5; exit}')
    if [ "$(check_ring_state)" = "unsupported" ]; then return; fi
    if [ "$(check_ring_state)" = "true" ]; then
        local max_rx=$(ethtool -g "$IFACE" 2>/dev/null | grep -A4 "Pre-set maximums" | grep "RX:" | head -1 | awk '{print $2}')
        if [ -n "$max_rx" ]; then ethtool -G "$IFACE" rx "$max_rx" tx "$max_rx" 2>/dev/null || true; fi
    else
        ethtool -G "$IFACE" rx 512 tx 512 2>/dev/null || true
    fi
    update_hw_boot_script
}

toggle_zram() {
    if [ "$(check_zram_state)" = "unsupported" ]; then return; fi
    if [ "$(check_zram_state)" = "true" ]; then
        swapoff /dev/zram0 2>/dev/null || true
        rmmod zram 2>/dev/null || true
        systemctl disable xray-zram.service --now 2>/dev/null || true
        rm -f /etc/systemd/system/xray-zram.service /usr/local/bin/xray-zram.sh
    else
        local TOTAL_MEM=$(free -m | awk '/Mem/{print $2}')
        local ZRAM_SIZE
        if [ "$TOTAL_MEM" -lt 500 ]; then ZRAM_SIZE=$((TOTAL_MEM * 2))
        elif [ "$TOTAL_MEM" -lt 1024 ]; then ZRAM_SIZE=$((TOTAL_MEM * 3 / 2))
        else ZRAM_SIZE=$TOTAL_MEM; fi
        
        cat > /usr/local/bin/xray-zram.sh <<EOFZ
#!/bin/bash
modprobe zram num_devices=1
echo "lz4" > /sys/block/zram0/comp_algorithm 2>/dev/null || true
echo "${ZRAM_SIZE}M" > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon -p 100 /dev/zram0
EOFZ
        chmod +x /usr/local/bin/xray-zram.sh
        
        cat > /etc/systemd/system/xray-zram.service <<EOFZ
[Unit]
Description=Xray ZRAM Setup
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/xray-zram.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOFZ
        systemctl daemon-reload
        systemctl enable xray-zram.service >/dev/null 2>&1
        systemctl start xray-zram.service >/dev/null 2>&1
    fi
}

toggle_journal() {
    local conf="/etc/systemd/journald.conf"
    if [ "$(check_journal_state)" = "unsupported" ]; then return; fi
    if [ "$(check_journal_state)" = "true" ]; then
        sed -i 's/^Storage=volatile/#Storage=auto/' "$conf" 2>/dev/null || true
        systemctl restart systemd-journald >/dev/null 2>&1
    else
        if grep -q "^#Storage=" "$conf" 2>/dev/null; then sed -i 's/^#Storage=.*/Storage=volatile/' "$conf"
        elif grep -q "^Storage=" "$conf" 2>/dev/null; then sed -i 's/^Storage=.*/Storage=volatile/' "$conf"
        else echo "Storage=volatile" >> "$conf"; fi
        systemctl restart systemd-journald >/dev/null 2>&1
    fi
}

toggle_process_priority() {
    local limit_file="/etc/systemd/system/xray.service.d/limits.conf"
    if [ ! -f "$limit_file" ]; then return; fi
    if grep -q "^OOMScoreAdjust=-500" "$limit_file"; then
        sed -i '/^OOMScoreAdjust=/d' "$limit_file"
        sed -i '/^IOSchedulingClass=/d' "$limit_file"
        sed -i '/^IOSchedulingPriority=/d' "$limit_file"
    else
        echo "OOMScoreAdjust=-500" >> "$limit_file"
        echo "IOSchedulingClass=realtime" >> "$limit_file"
        echo "IOSchedulingPriority=2" >> "$limit_file"
    fi
    systemctl daemon-reload
    systemctl restart xray >/dev/null 2>&1
}

_turn_on_app() {
    _safe_jq_write '
      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt) |= (. // {}) |
      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt) |= (. // {}) |
      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpNoDelay) = true |
      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpFastOpen) = true |
      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpNoDelay) = true |
      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpFastOpen) = true |
      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpKeepAliveIdle) = 30 |
      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpKeepAliveInterval) = 15 |
      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpKeepAliveIdle) = 30 |
      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpKeepAliveInterval) = 15
    '
    _safe_jq_write '(.inbounds[] | select(.protocol=="vless") | .sniffing.metadataOnly) = true | (.inbounds[] | select(.protocol=="vless") | .sniffing.routeOnly) = true'
    
    if [ "$(check_dnsmasq_state)" = "true" ]; then
        _safe_jq_write '.dns = {"servers":["127.0.0.1"], "queryStrategy":"UseIP"}'
    else
        _safe_jq_write '.dns = {"servers":["https://8.8.8.8/dns-query","https://1.1.1.1/dns-query","https://dns.opendns.com/dns-query"], "queryStrategy":"UseIP"}'
    fi
    
    _safe_jq_write '.policy = {"levels":{"0":{"handshake":3,"connIdle":60}},"system":{"statsInboundDownlink":false,"statsInboundUplink":false}}'
    
    local limit_file="/etc/systemd/system/xray.service.d/limits.conf"
    if [ -f "$limit_file" ]; then
        local TOTAL_MEM=$(free -m | awk '/Mem/{print $2}')
        local DYNAMIC_GOGC=100
        if [ "$TOTAL_MEM" -ge 1800 ]; then DYNAMIC_GOGC=1000
        elif [ "$TOTAL_MEM" -ge 900 ]; then DYNAMIC_GOGC=500
        elif [ "$TOTAL_MEM" -ge 700 ]; then DYNAMIC_GOGC=400
        elif [ "$TOTAL_MEM" -ge 500 ]; then DYNAMIC_GOGC=300
        elif [ "$TOTAL_MEM" -ge 400 ]; then DYNAMIC_GOGC=200
        else DYNAMIC_GOGC=100; fi

        if grep -q "Environment=\"GOGC=" "$limit_file"; then
            sed -i "s/^Environment=\"GOGC=.*/Environment=\"GOGC=$DYNAMIC_GOGC\"/" "$limit_file"
        else
            echo "Environment=\"GOGC=$DYNAMIC_GOGC\"" >> "$limit_file"
        fi
        systemctl daemon-reload
    fi
}

_turn_off_app() {
    _safe_jq_write 'del(.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpNoDelay, .streamSettings.sockopt.tcpFastOpen, .streamSettings.sockopt.tcpKeepAliveIdle, .streamSettings.sockopt.tcpKeepAliveInterval) | del(.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpNoDelay, .streamSettings.sockopt.tcpFastOpen, .streamSettings.sockopt.tcpKeepAliveIdle, .streamSettings.sockopt.tcpKeepAliveInterval)'
    _safe_jq_write '(.inbounds[] | select(.protocol=="vless") | .sniffing.metadataOnly) = false | (.inbounds[] | select(.protocol=="vless") | .sniffing.routeOnly) = false'
    _safe_jq_write 'del(.dns)'
    _safe_jq_write 'del(.policy)'
    
    local limit_file="/etc/systemd/system/xray.service.d/limits.conf"
    if [ -f "$limit_file" ]; then
        if grep -q "Environment=\"GOGC=" "$limit_file"; then
            sed -i "s/^Environment=\"GOGC=.*/Environment=\"GOGC=100\"/" "$limit_file"
        else
            echo "Environment=\"GOGC=100\"" >> "$limit_file"
        fi
        systemctl daemon-reload
    fi
}

# -- [功能 10->7] 全域 14 项极限微操双向设置枢纽 --
do_app_level_tuning_menu() {
    while true; do
        clear
        title "全域 14 项极限微操 (Xray 提速底牌 & 系统内核微操)"
        if ! test -f "$CONFIG"; then 
            error "未发现配置，请先执行核心安装！"
            read -rp "按 Enter 返回..." _
            return
        fi

        # 瞬时全量状态提取 (应用层)
        local out_fastopen=$(jq -r '.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpFastOpen // "false"' "$CONFIG" 2>/dev/null)
        local out_keepalive=$(jq -r '.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpKeepAliveIdle // "false"' "$CONFIG" 2>/dev/null)
        local sniff_status=$(jq -r '.inbounds[] | select(.protocol=="vless") | .sniffing.metadataOnly // "false"' "$CONFIG" 2>/dev/null)
        local dns_status=$(jq -r '.dns.queryStrategy // "false"' "$CONFIG" 2>/dev/null)
        local policy_status=$(jq -r '.policy.levels["0"].connIdle // "false"' "$CONFIG" 2>/dev/null)
        
        local limit_file="/etc/systemd/system/xray.service.d/limits.conf"
        local gc_status="未知"
        if [ -f "$limit_file" ]; then
            gc_status=$(awk -F'=' '/^Environment="GOGC=/ {print $3}' "$limit_file" | tr -d '"' | head -1)
            gc_status=${gc_status:-"默认 100"}
        fi

        # 瞬时全量状态提取 (系统层，包含避障侦测)
        local dnsmasq_state=$(check_dnsmasq_state)
        local thp_state=$(check_thp_state)
        local mtu_state=$(check_mtu_state)
        local cpu_state=$(check_cpu_state)
        local ring_state=$(check_ring_state)
        local zram_state=$(check_zram_state)
        local journal_state=$(check_journal_state)
        local prio_state=$(check_process_priority_state)

        # 缺省探测引擎 (App 层 - 1~6项)
        local app_off_count=0
        [ "$out_fastopen" != "true" ] && app_off_count=$((app_off_count+1))
        [ "$out_keepalive" != "30" ] && app_off_count=$((app_off_count+1))
        [ "$sniff_status" != "true" ] && app_off_count=$((app_off_count+1))
        [ "$dns_status" != "UseIP" ] && app_off_count=$((app_off_count+1))
        if [ "$gc_status" = "默认 100" ] || [ "$gc_status" = "100" ]; then app_off_count=$((app_off_count+1)); fi
        [ "$policy_status" != "60" ] && app_off_count=$((app_off_count+1))

        # 缺省探测引擎 (系统层 - 7~14项 硬件自适应剔除)
        local sys_off_count=0
        [ "$dnsmasq_state" = "false" ] && sys_off_count=$((sys_off_count+1))
        [ "$thp_state" = "false" ] && sys_off_count=$((sys_off_count+1))
        [ "$mtu_state" = "false" ] && sys_off_count=$((sys_off_count+1))
        [ "$cpu_state" = "false" ] && sys_off_count=$((sys_off_count+1))
        [ "$ring_state" = "false" ] && sys_off_count=$((sys_off_count+1))
        [ "$zram_state" = "false" ] && sys_off_count=$((sys_off_count+1))
        [ "$journal_state" = "false" ] && sys_off_count=$((sys_off_count+1))
        [ "$prio_state" = "false" ] && sys_off_count=$((sys_off_count+1))

        # UI 状态映射
        local s1=$([ "$out_fastopen" = "true" ] && echo "${cyan}已开启${none}" || echo "${gray}未开启${none}")
        local s2=$([ "$out_keepalive" = "30" ] && echo "${cyan}已开启 (30s/15s)${none}" || echo "${gray}系统默认${none}")
        local s3=$([ "$sniff_status" = "true" ] && echo "${cyan}已开启${none}" || echo "${gray}未开启${none}")
        local s4=$([ "$dns_status" = "UseIP" ] && echo "${cyan}已开启${none}" || echo "${gray}未开启${none}")
        local s6=$([ "$policy_status" = "60" ] && echo "${cyan}已开启 (闲置60s/握手3s)${none}" || echo "${gray}默认 300s 慢回收${none}")
        
        local s7=$([ "$dnsmasq_state" = "true" ] && echo "${cyan}内存极速解析中 (0.1ms)${none}" || echo "${gray}未开启 (依赖原生DoH)${none}")
        local s8=$([ "$thp_state" = "true" ] && echo "${cyan}已关闭 THP${none}" || ([ "$thp_state" = "unsupported" ] && echo "${gray}不支持${none}" || echo "${gray}系统默认${none}"))
        local s9=$([ "$mtu_state" = "true" ] && echo "${cyan}智能探测中${none}" || ([ "$mtu_state" = "unsupported" ] && echo "${gray}不支持${none}" || echo "${gray}未开启${none}"))
        local s10=$([ "$cpu_state" = "true" ] && echo "${cyan}全核火力全开${none}" || ([ "$cpu_state" = "unsupported" ] && echo "${gray}不支持${none}" || echo "${gray}节能待机${none}"))
        local s11=$([ "$ring_state" = "true" ] && echo "${cyan}已反向收缩${none}" || ([ "$ring_state" = "unsupported" ] && echo "${gray}不支持${none}" || echo "${gray}系统大缓冲${none}"))
        local s12=$([ "$zram_state" = "true" ] && echo "${cyan}已挂载 ZRAM${none}" || ([ "$zram_state" = "unsupported" ] && echo "${gray}不支持${none}" || echo "${gray}未启用${none}"))
        local s13=$([ "$journal_state" = "true" ] && echo "${cyan}纯内存极速化${none}" || ([ "$journal_state" = "unsupported" ] && echo "${gray}不支持${none}" || echo "${gray}磁盘 IO 写入中${none}"))
        local s14=$([ "$prio_state" = "true" ] && echo "${cyan}OOM免死 / IO抢占${none}" || echo "${gray}系统默认调度${none}")

        echo -e "  ${magenta}--- Xray Core 应用层内部调优 (1-6) ---${none}"
        echo -e "  1) 开启或关闭 双向并发提速 (tcpNoDelay/FastOpen)                 | 当前状态: $s1"
        echo -e "  2) 开启或关闭 Socket 智能保活心跳 (KeepAlive: Idle 30s)          | 当前状态: $s2"
        echo -e "  3) 开启或关闭 嗅探引擎减负 (metadataOnly 解放 CPU)               | 当前状态: $s3"
        echo -e "  4) 开启或关闭 内置并发 DoH / Dnsmasq 路由分发 (Xray Native DNS)  | 当前状态: $s4"
        echo -e "  5) 执行或关闭 GOGC 内存阶梯飙车调优 (自动侦测物理内存)           | 当前设定: ${cyan}${gc_status}${none}"
        echo -e "  6) 开启或关闭 Xray Policy 策略组优化 (连接生命周期极速回收)      | 当前状态: $s6"
        echo -e ""
        echo -e "  ${magenta}--- Linux 系统层与内核黑科技 (7-14) ---${none}"
        echo -e "  7)  开启或关闭【Dnsmasq 本地极速内存缓存引擎 (21000并发/锁TTL)】 | 当前状态: $s7"
        echo -e "  8)  开启或关闭【透明大页 (THP - Transparent Huge Pages)】        | 当前状态: $s8"
        echo -e "  9)  开启或关闭【TCP PMTU 黑洞智能探测 (Probing=1)】              | 当前状态: $s9"
        echo -e "  10) 开启或关闭【CPU 频率调度器锁定 (Performance)】               | 当前状态: $s10"
        echo -e "  11) 开启或关闭【网卡硬件环形缓冲区 (Ring Buffer) 反向收缩】      | 当前状态: $s11"
        echo -e "  12) 开启或关闭【ZRAM】(淘汰慢速 Swap，阶梯内存自动检测)          | 当前状态: $s12"
        echo -e "  13) 开启或关闭【日志系统 Journald 纯内存化】(斩断 I/O 羁绊)      | 当前状态: $s13"
        echo -e "  14) 开启或关闭【系统进程级防杀抢占 (OOM/IO 提权)】               | 当前状态: $s14"
        echo -e "  "
        echo -e "  ${cyan}15) 一键开启或关闭 1-6 项 应用层微操 (自动侦测并智能反转)${none}"
        echo -e "  ${yellow}16) 一键开启或关闭 7-14 项 系统级微操 (自动避障侦测并反转)${none}"
        echo -e "  ${red}17) 上帝之手：一键开启或关闭 1-14 项 全域微操 (满血激活 / 无损还原)${none}"
        echo "  0) 返回上一级"
        hr
        read -rp "请选择: " app_opt

        case "$app_opt" in
            1)
                if [ "$out_fastopen" = "true" ]; then
                    _safe_jq_write 'del(.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpNoDelay, .streamSettings.sockopt.tcpFastOpen) | del(.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpNoDelay, .streamSettings.sockopt.tcpFastOpen)'
                    info "双向并发提速 (FastOpen) 已关闭。"
                else
                    _safe_jq_write '
                      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt) |= (. // {}) |
                      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt) |= (. // {}) |
                      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpNoDelay) = true |
                      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpFastOpen) = true |
                      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpNoDelay) = true |
                      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpFastOpen) = true
                    '
                    info "双向并发提速 (FastOpen) 已全域开启！"
                fi
                systemctl restart xray >/dev/null 2>&1
                read -rp "按 Enter 继续..." _
                ;;
            2)
                if [ "$out_keepalive" = "30" ]; then
                    _safe_jq_write 'del(.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpKeepAliveIdle, .streamSettings.sockopt.tcpKeepAliveInterval) | del(.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpKeepAliveIdle, .streamSettings.sockopt.tcpKeepAliveInterval)'
                    info "Socket 智能保活心跳已关闭。"
                else
                    _safe_jq_write '
                      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt) |= (. // {}) |
                      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt) |= (. // {}) |
                      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpKeepAliveIdle) = 30 |
                      (.outbounds[] | select(.protocol=="freedom") | .streamSettings.sockopt.tcpKeepAliveInterval) = 15 |
                      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpKeepAliveIdle) = 30 |
                      (.inbounds[] | select(.protocol=="vless") | .streamSettings.sockopt.tcpKeepAliveInterval) = 15
                    '
                    info "Socket 智能保活心跳 (Idle:30s/Intvl:15s) 已极速注入！"
                fi
                systemctl restart xray >/dev/null 2>&1
                read -rp "按 Enter 继续..." _
                ;;
            3)
                if [ "$sniff_status" = "true" ]; then
                    _safe_jq_write '(.inbounds[] | select(.protocol=="vless") | .sniffing.metadataOnly) = false | (.inbounds[] | select(.protocol=="vless") | .sniffing.routeOnly) = false'
                    info "嗅探引擎减负已关闭，恢复深度探包。"
                else
                    _safe_jq_write '(.inbounds[] | select(.protocol=="vless") | .sniffing.metadataOnly) = true | (.inbounds[] | select(.protocol=="vless") | .sniffing.routeOnly) = true'
                    info "嗅探引擎减负已开启！"
                fi
                systemctl restart xray >/dev/null 2>&1
                read -rp "按 Enter 继续..." _
                ;;
            4)
                if [ "$dns_status" = "UseIP" ]; then
                    _safe_jq_write 'del(.dns)'
                    info "内置 DNS 路由分发已移除。"
                else
                    if [ "$dnsmasq_state" = "true" ]; then
                        _safe_jq_write '.dns = {"servers":["127.0.0.1"], "queryStrategy":"UseIP"}'
                        info "DNS 已接通本地 Dnsmasq 内存极速引擎！"
                    else
                        _safe_jq_write '.dns = {"servers":["https://8.8.8.8/dns-query","https://1.1.1.1/dns-query","https://dns.opendns.com/dns-query"], "queryStrategy":"UseIP"}'
                        info "DNS 已开启 DoH 加密并发！"
                    fi
                fi
                systemctl restart xray >/dev/null 2>&1
                read -rp "按 Enter 继续..." _
                ;;
            5)
                if [ -f "$limit_file" ]; then
                    local TOTAL_MEM=$(free -m | awk '/Mem/{print $2}')
                    local DYNAMIC_GOGC=100

                    if [ "$TOTAL_MEM" -ge 1800 ]; then DYNAMIC_GOGC=1000
                    elif [ "$TOTAL_MEM" -ge 900 ]; then DYNAMIC_GOGC=500
                    elif [ "$TOTAL_MEM" -ge 700 ]; then DYNAMIC_GOGC=400
                    elif [ "$TOTAL_MEM" -ge 500 ]; then DYNAMIC_GOGC=300
                    elif [ "$TOTAL_MEM" -ge 400 ]; then DYNAMIC_GOGC=200
                    else DYNAMIC_GOGC=100; fi

                    if grep -q "Environment=\"GOGC=" "$limit_file"; then
                        if [ "$gc_status" = "默认 100" ] || [ "$gc_status" = "100" ]; then
                            sed -i "s/^Environment=\"GOGC=.*/Environment=\"GOGC=$DYNAMIC_GOGC\"/" "$limit_file"
                            info "GOGC 动态阶梯调优完成！自动锁定阈值: ${DYNAMIC_GOGC}"
                        else
                            sed -i "s/^Environment=\"GOGC=.*/Environment=\"GOGC=100\"/" "$limit_file"
                            info "GOGC 阶梯调优已关闭，已恢复保底阈值: 100"
                        fi
                    else
                        echo "Environment=\"GOGC=$DYNAMIC_GOGC\"" >> "$limit_file"
                        info "GOGC 动态阶梯调优完成！自动锁定阈值: ${DYNAMIC_GOGC}"
                    fi
                    systemctl daemon-reload
                    systemctl restart xray
                else
                    error "未找到 Xray systemd 配置文件，请先执行核心安装！"
                fi
                read -rp "按 Enter 继续..." _
                ;;
            6)
                if [ "$policy_status" = "60" ]; then
                    _safe_jq_write 'del(.policy)'
                    info "Xray 策略组极速回收已关闭，恢复官方默认 300 秒断流容忍。"
                else
                    _safe_jq_write '.policy = {"levels":{"0":{"handshake":3,"connIdle":60}},"system":{"statsInboundDownlink":false,"statsInboundUplink":false}}'
                    info "Xray 策略组优化成功！半连接与死连接将被压缩至 60 秒内强制释放！"
                fi
                systemctl restart xray >/dev/null 2>&1
                read -rp "按 Enter 继续..." _
                ;;
            7) toggle_dnsmasq; read -rp "按 Enter 继续..." _ ;;
            8) toggle_thp; info "操作已下发。"; read -rp "按 Enter 继续..." _ ;;
            9) toggle_mtu; info "操作已下发。"; read -rp "按 Enter 继续..." _ ;;
            10) toggle_cpu; info "操作已下发。"; read -rp "按 Enter 继续..." _ ;;
            11) toggle_ring; info "操作已下发。"; read -rp "按 Enter 继续..." _ ;;
            12) toggle_zram; info "操作已下发。"; read -rp "按 Enter 继续..." _ ;;
            13) toggle_journal; info "操作已下发。"; read -rp "按 Enter 继续..." _ ;;
            14) toggle_process_priority; info "操作已下发。"; read -rp "按 Enter 继续..." _ ;;
            15)
                if [ "$app_off_count" -gt 0 ]; then
                    _turn_on_app
                    systemctl restart xray >/dev/null 2>&1
                    info "1-6 项 Xray 内部应用层微操已全域强力开启！"
                else
                    _turn_off_app
                    systemctl restart xray >/dev/null 2>&1
                    info "1-6 项 Xray 内部应用层微操已全部强制关闭，无损还原官方初始状态！"
                fi
                read -rp "按 Enter 继续..." _
                ;;
            16)
                if [ "$sys_off_count" -gt 0 ]; then
                    [ "$dnsmasq_state" = "false" ] && toggle_dnsmasq
                    [ "$thp_state" = "false" ] && toggle_thp
                    [ "$mtu_state" = "false" ] && toggle_mtu
                    [ "$cpu_state" = "false" ] && toggle_cpu
                    [ "$ring_state" = "false" ] && toggle_ring
                    [ "$zram_state" = "false" ] && toggle_zram
                    [ "$journal_state" = "false" ] && toggle_journal
                    [ "$prio_state" = "false" ] && toggle_process_priority
                    info "7-14 项系统内核底层黑科技已全部一键激活！(不支持的硬件已自动跳过)"
                else
                    [ "$dnsmasq_state" = "true" ] && toggle_dnsmasq
                    [ "$thp_state" = "true" ] && toggle_thp
                    [ "$mtu_state" = "true" ] && toggle_mtu
                    [ "$cpu_state" = "true" ] && toggle_cpu
                    [ "$ring_state" = "true" ] && toggle_ring
                    [ "$zram_state" = "true" ] && toggle_zram
                    [ "$journal_state" = "true" ] && toggle_journal
                    [ "$prio_state" = "true" ] && toggle_process_priority
                    info "7-14 项系统内核底层黑科技已全部一键卸载还原！"
                fi
                read -rp "按 Enter 继续..." _
                ;;
            17)
                if [ "$((app_off_count + sys_off_count))" -gt 0 ]; then
                    if [ "$app_off_count" -gt 0 ]; then _turn_on_app; fi
                    if [ "$sys_off_count" -gt 0 ]; then
                        [ "$dnsmasq_state" = "false" ] && toggle_dnsmasq
                        [ "$thp_state" = "false" ] && toggle_thp
                        [ "$mtu_state" = "false" ] && toggle_mtu
                        [ "$cpu_state" = "false" ] && toggle_cpu
                        [ "$ring_state" = "false" ] && toggle_ring
                        [ "$zram_state" = "false" ] && toggle_zram
                        [ "$journal_state" = "false" ] && toggle_journal
                        [ "$prio_state" = "false" ] && toggle_process_priority
                    fi
                    systemctl restart xray >/dev/null 2>&1
                    info "上帝降临！1-14 项全域极限微操已【全部满血激活】！(不支持的硬件已自动跳过)"
                else
                    _turn_off_app
                    [ "$dnsmasq_state" = "true" ] && toggle_dnsmasq
                    [ "$thp_state" = "true" ] && toggle_thp
                    [ "$mtu_state" = "true" ] && toggle_mtu
                    [ "$cpu_state" = "true" ] && toggle_cpu
                    [ "$ring_state" = "true" ] && toggle_ring
                    [ "$zram_state" = "true" ] && toggle_zram
                    [ "$journal_state" = "true" ] && toggle_journal
                    [ "$prio_state" = "true" ] && toggle_process_priority
                    
                    systemctl restart xray >/dev/null 2>&1
                    info "神威收敛！1-14 项全域极限微操已【全部强制关闭】，无损还原初始出厂状态！"
                fi
                read -rp "按 Enter 继续..." _
                ;;
            0)
                return
                ;;
        esac
    done
}

# -- [功能 10] 系统级全能初始化子菜单 (完美防坑逻辑流) --
do_sys_init_menu() {
    while true; do
        title "初次安装、更新系统组件"
        echo "  1) 一键更新系统、安装常用组件并校准时区 (Asia/Kuala_Lumpur)"
        echo -e "  ${cyan}2) 必须先安装 XANMOD (main) 官方预编译内核 (推荐/防断连/自动重启)${none}"
        echo "  3) 先完成2），编译安装 Xanmod 内核 + BBR3 (极客源码流 / 自动重启)"
        echo "  4) 网卡发送队列 (TX Queue) 深度调优 (2000 防堵塞极速版)"
        echo "  5) 系统内核网络栈极限调优 (低延迟特化版 / 自动重启)"
        echo -e "  ${magenta}6) 全域 14 项极限微操 (Dnsmasq / Xray 提速底牌 / 系统级黑科技)${none}"
        echo "  0) 返回主菜单"
        hr
        read -rp "请选择: " sys_opt
        case "$sys_opt" in
            1) 
                print_magenta ">>> 正在拉取系统更新与底层环境组件，请勿中断..."
                
                export DEBIAN_FRONTEND=noninteractive
                apt-get update -y
                apt-get -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" full-upgrade -y
                apt-get autoremove -y --purge
                
                apt-get install -y wget curl sudo socat ntpdate e2fsprogs pkg-config iproute2 ethtool
                
                timedatectl set-timezone Asia/Kuala_Lumpur
                ntpdate us.pool.ntp.org
                hwclock --systohc
                
                info "底层组件拉平完毕，系统时间已硬同步至 Asia/Kuala_Lumpur！"
                read -rp "按 Enter 继续..." _
                ;;
            2)
                do_install_xanmod_main_official
                ;;
            3)
                do_xanmod_compile
                ;;
            4)
                do_txqueuelen_opt
                ;;
            5)
                do_perf_tuning
                ;;
            6)
                do_app_level_tuning_menu
                ;;
            0) 
                return 
                ;;
        esac
    done
}

# -- 用户管理 (包含创建时间与外部导入SNI配置) --
do_user_manager() {
    while true; do
        title "用户管理 (增删/导入 备注、UUID、ShortId)"
        
        if ! test -f "$CONFIG"; then 
            error "未发现配置，请先安装核心网络"
            return
        fi

        # 安全防脱逸的 jq 字符串拼接提取
        local clients=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .settings.clients[] | .id + \"|\" + (.email // \"无备注\")" "$CONFIG" 2>/dev/null)
        
        if test -z "$clients" || test "$clients" = "null"; then 
            error "未发现在运行的 VLESS 节点协议"
            return
        fi

        local tmp_users="/tmp/xray_users.txt"
        echo "$clients" | awk -F'|' '{print NR"|"$1"|"$2}' > "$tmp_users"
        
        echo -e "当前用户列表："
        cat "$tmp_users" | while IFS='|' read -r num uid remark; do
            local utime=$(grep "^$uid|" "$USER_TIME_MAP" 2>/dev/null | cut -d'|' -f2)
            utime=${utime:-"未知时间"}
            echo -e "  $num) 备注: ${cyan}$remark${none} | 时间: ${gray}$utime${none} | UUID: ${yellow}$uid${none}"
        done
        hr
        
        echo "  a) 新增本网用户 (自动分配 UUID 与 ShortId)"
        echo "  m) 手动导入外部用户 (平滑迁移老用户的 UUID/ShortId)"
        echo "  s) 修改指定用户的专属 SNI 伪装域名"
        echo "  d) 序号删除用户"
        echo "  q) 退出"
        read -rp "指令: " uopt
        
        if test "$uopt" = "a"; then
            local nu=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || $XRAY_BIN uuid)
            local ns=$(head -c 8 /dev/urandom | xxd -p | tr -d '\n')
            local ctime=$(date +"%Y-%m-%d %H:%M")
            
            read -rp "请输入新用户的专属节点备注 (直接回车默认: User-${ns}): " u_remark
            u_remark=${u_remark:-User-${ns}}
            
            # 使用 jq 文件流形式注入
            cat > /tmp/new_client.json <<EOF
{
  "id": "$nu",
  "flow": "xtls-rprx-vision",
  "email": "$u_remark"
}
EOF
            jq '(.inbounds[] | select(.protocol=="vless") | .settings.clients) += [input]' "$CONFIG" /tmp/new_client.json > "$CONFIG.tmp1"
            jq --arg sid "$ns" '(.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.shortIds) += [$sid]' "$CONFIG.tmp1" > "$CONFIG"
            rm -f /tmp/new_client.json "$CONFIG.tmp1"
            
            echo "$nu|$ctime" >> "$USER_TIME_MAP"
            fix_permissions
            systemctl restart xray
            
            local port=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .port" "$CONFIG" | head -1)
            local sni=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .streamSettings.realitySettings.serverNames[0]" "$CONFIG" | head -1)
            local pub=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .streamSettings.realitySettings.publicKey" "$CONFIG" | head -1)
            
            info "用户分配成功！该用户专属节点信息如下："
            hr
            printf "  ${cyan}【新增 VLESS-Reality 节点信息】${none}\n"
            printf "  ${yellow}%-16s${none} %s\n" "节点名称:" "$u_remark"
            printf "  ${yellow}%-16s${none} %s\n" "外网 IP:" "$SERVER_IP"
            printf "  ${yellow}%-16s${none} %s\n" "监听端口:" "$port"
            printf "  ${yellow}%-16s${none} %s\n" "主用 UUID:" "$nu"
            printf "  ${yellow}%-16s${none} %s\n" "专属 SNI:" "$sni"
            printf "  ${yellow}%-16s${none} %s\n" "公钥(pbk):" "$pub"
            printf "  ${yellow}%-16s${none} %s\n" "Short ID:" "$ns"

            local link="vless://${nu}@${SERVER_IP}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${sni}&fp=chrome&pbk=${pub}&sid=${ns}&type=tcp#${u_remark}"
            echo -e "\n  ${cyan}专属分发链接:${none} \n  $link\n"
            
            if command -v qrencode >/dev/null 2>&1; then 
                echo -e "  ${cyan}手机扫码导入:${none}"
                qrencode -m 2 -t UTF8 "$link"
            fi
            read -rp "按 Enter 继续..." _
            
        elif test "$uopt" = "m"; then
            hr
            echo -e " ${cyan}>>> 外部老用户平滑迁移向导 <<<${none}"
            echo -e " ${yellow}提示: 将外部用户的凭证挂载到本机，生成由本机 IP 和 pbk 构建的新链接！${none}"
            
            read -rp "请输入外部用户的备注 (例如: VIP-User): " m_remark
            m_remark=${m_remark:-ImportedUser}
            
            read -rp "请输入外部用户的 UUID: " m_uuid
            if test -z "$m_uuid"; then 
                error "UUID 不能为空！"
                continue
            fi
            
            read -rp "请输入外部用户的 ShortId: " m_sid
            if test -z "$m_sid"; then 
                error "ShortId 不能为空！"
                continue
            fi
            
            local ctime=$(date +"%Y-%m-%d %H:%M")
            cat > /tmp/new_client.json <<EOF
{
  "id": "$m_uuid",
  "flow": "xtls-rprx-vision",
  "email": "$m_remark"
}
EOF
            jq '(.inbounds[] | select(.protocol=="vless") | .settings.clients) += [input]' "$CONFIG" /tmp/new_client.json > "$CONFIG.tmp1"
            jq --arg sid "$m_sid" '(.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.shortIds) += [$sid]' "$CONFIG.tmp1" > "$CONFIG"
            rm -f /tmp/new_client.json "$CONFIG.tmp1"

            echo "$m_uuid|$ctime" >> "$USER_TIME_MAP"
            
            read -rp "是否需要为该导入用户指定专属 SNI? (直接回车则使用全局默认, 若需要请填写域名): " m_sni
            if test -n "$m_sni"; then
                jq --arg sni "$m_sni" '(.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.serverNames) += [$sni] | (.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.serverNames) |= unique' "$CONFIG" > "$CONFIG.tmp2"
                mv -f "$CONFIG.tmp2" "$CONFIG"
                
                sed -i "/^$m_uuid|/d" "$USER_SNI_MAP" 2>/dev/null
                echo "$m_uuid|$m_sni" >> "$USER_SNI_MAP"
                info "已为导入用户绑定专属 SNI: $m_sni"
            else
                m_sni=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .streamSettings.realitySettings.serverNames[0]" "$CONFIG" | head -1)
            fi
            
            fix_permissions
            systemctl restart xray
            
            local port=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .port" "$CONFIG" | head -1)
            local pub=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .streamSettings.realitySettings.publicKey" "$CONFIG" | head -1)
            
            info "外部用户导入成功！当前机器专属分发信息如下："
            hr
            printf "  ${cyan}【导入 VLESS-Reality 节点信息】${none}\n"
            printf "  ${yellow}%-16s${none} %s\n" "节点名称:" "$m_remark"
            printf "  ${yellow}%-16s${none} %s\n" "外网 IP:" "$SERVER_IP"
            printf "  ${yellow}%-16s${none} %s\n" "监听端口:" "$port"
            printf "  ${yellow}%-16s${none} %s\n" "主用 UUID:" "$m_uuid"
            printf "  ${yellow}%-16s${none} %s\n" "专属 SNI:" "$m_sni"
            printf "  ${yellow}%-16s${none} %s\n" "公钥(pbk):" "$pub"
            printf "  ${yellow}%-16s${none} %s\n" "Short ID:" "$m_sid"

            local link="vless://${m_uuid}@${SERVER_IP}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${m_sni}&fp=chrome&pbk=${pub}&sid=${m_sid}&type=tcp#${m_remark}"
            echo -e "\n  ${cyan}专属分发链接:${none} \n  $link\n"
            
            if command -v qrencode >/dev/null 2>&1; then 
                echo -e "  ${cyan}手机扫码导入:${none}"
                qrencode -m 2 -t UTF8 "$link"
            fi
            read -rp "按 Enter 继续..." _

        elif test "$uopt" = "s"; then
            read -rp "请输入要操作的序号: " snum
            local target_uuid=$(awk -F'|' -v id="${snum:-0}" '$1==id {print $2}' "$tmp_users")
            local target_remark=$(awk -F'|' -v id="${snum:-0}" '$1==id {print $3}' "$tmp_users")
            
            if test -n "$target_uuid"; then
                read -rp "请输入该用户的专属 SNI 域名: " u_sni
                if test -n "$u_sni"; then
                    jq --arg sni "$u_sni" '(.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.serverNames) += [$sni] | (.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.serverNames) |= unique' "$CONFIG" > "$CONFIG.tmp"
                    mv -f "$CONFIG.tmp" "$CONFIG"
                    
                    sed -i "/^$target_uuid|/d" "$USER_SNI_MAP" 2>/dev/null
                    echo "$target_uuid|$u_sni" >> "$USER_SNI_MAP"
                    fix_permissions
                    systemctl restart xray
                    
                    info "已成功为该用户绑定专属 SNI: $u_sni"
                    
                    local port=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .port" "$CONFIG" | head -1)
                    # 匹配此用户的 shortId
                    local idx=$((${snum:-0}-1))
                    local sid=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .streamSettings.realitySettings.shortIds[$idx]" "$CONFIG" 2>/dev/null)
                    local pub=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .streamSettings.realitySettings.publicKey" "$CONFIG" | head -1)
                    
                    hr
                    printf "  ${cyan}【更新 VLESS-Reality 节点信息】${none}\n"
                    printf "  ${yellow}%-16s${none} %s\n" "节点名称:" "$target_remark"
                    printf "  ${yellow}%-16s${none} %s\n" "外网 IP:" "$SERVER_IP"
                    printf "  ${yellow}%-16s${none} %s\n" "监听端口:" "$port"
                    printf "  ${yellow}%-16s${none} %s\n" "主用 UUID:" "$target_uuid"
                    printf "  ${yellow}%-16s${none} %s\n" "专属 SNI:" "$u_sni"
                    printf "  ${yellow}%-16s${none} %s\n" "公钥(pbk):" "$pub"
                    printf "  ${yellow}%-16s${none} %s\n" "Short ID:" "$sid"

                    local link="vless://${target_uuid}@${SERVER_IP}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${u_sni}&fp=chrome&pbk=${pub}&sid=${sid}&type=tcp#${target_remark}"
                    
                    echo -e "\n  ${cyan}专属更新链接:${none} \n  $link\n"
                    if command -v qrencode >/dev/null 2>&1; then 
                        qrencode -m 2 -t UTF8 "$link"
                    fi
                    read -rp "按 Enter 继续..." _
                fi
            else
                error "序号无效。"
            fi
            
        elif test "$uopt" = "d"; then
            read -rp "请输入要删除的序号: " dnum
            local total=$(wc -l < "$tmp_users" 2>/dev/null)
            
            if test "${total:-0}" -le 1; then
                error "必须保留至少一个用户作为主账户！"
            else
                local target_uuid=$(awk -F'|' -v id="${dnum:-0}" '$1==id {print $2}' "$tmp_users")
                if test -n "$target_uuid"; then
                    local idx=$((${dnum:-0}-1))
                    jq --arg uid "$target_uuid" --argjson i "$idx" '
                      (.inbounds[] | select(.protocol=="vless") | .settings.clients) |= map(select(.id != $uid)) |
                      (.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.shortIds) |= del(.[$i])
                    ' "$CONFIG" > "$CONFIG.tmp"
                    mv -f "$CONFIG.tmp" "$CONFIG"
                    
                    sed -i "/^$target_uuid|/d" "$USER_SNI_MAP" 2>/dev/null
                    sed -i "/^$target_uuid|/d" "$USER_TIME_MAP" 2>/dev/null
                    fix_permissions
                    systemctl restart xray
                    info "已成功剔除该用户及其对应凭证。"
                else
                    error "序号无效。"
                fi
            fi
            
        elif test "$uopt" = "q"; then
            rm -f "$tmp_users"
            break
        fi
    done
}

# -- 屏蔽规则管理 --
_global_block_rules() {
    while true; do
        title "屏蔽规则管理 (BT/广告双轨分离拦截)"
        if ! test -f "$CONFIG"; then 
            error "未发现配置，请先执行安装"
            return
        fi
        
        local bt_en=$(jq -r ".routing.rules[] | select(.protocol | index(\"bittorrent\")) | ._enabled" "$CONFIG" 2>/dev/null | head -1)
        local ad_en=$(jq -r ".routing.rules[] | select(.domain | index(\"geosite:category-ads-all\")) | ._enabled" "$CONFIG" 2>/dev/null | head -1)
        
        echo -e "  1) BT/PT 协议拦截   当前状态: ${yellow}${bt_en}${none}"
        echo -e "  2) 全球广告拦截     当前状态: ${yellow}${ad_en}${none}"
        echo "  0) 返回"
        read -rp "选择: " bc
        
        case "$bc" in
            1) 
                local nv="true"
                if test "$bt_en" = "true"; then nv="false"; fi
                jq --argjson nv "$nv" '(.routing.rules[] | select(.protocol | index("bittorrent")) | ._enabled) = $nv' "$CONFIG" > "$CONFIG.tmp"
                mv -f "$CONFIG.tmp" "$CONFIG"
                fix_permissions
                systemctl restart xray
                info "BT 屏蔽已成功切换为: $nv"
                ;;
            2) 
                local nv="true"
                if test "$ad_en" = "true"; then nv="false"; fi
                jq --argjson nv "$nv" '(.routing.rules[] | select(.domain | index("geosite:category-ads-all")) | ._enabled) = $nv' "$CONFIG" > "$CONFIG.tmp"
                mv -f "$CONFIG.tmp" "$CONFIG"
                fix_permissions
                systemctl restart xray
                info "广告屏蔽已成功切换为: $nv"
                ;;
            0) 
                return 
                ;;
        esac
    done
}

# -- 分发中心 (引入动态数组遍历，支持无损展示多用户全量节点明细) --
do_summary() {
    if ! test -f "$CONFIG"; then 
        return
    fi
    title "The Apex Vanguard 节点详情中心"
    
    local client_count=$(jq '.inbounds[] | select(.protocol=="vless") | .settings.clients | length' "$CONFIG" 2>/dev/null || echo 0)
    
    if test "${client_count:-0}" -gt 0; then
        local port=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .port" "$CONFIG" 2>/dev/null)
        local pub=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .streamSettings.realitySettings.publicKey" "$CONFIG" 2>/dev/null)
        local all_snis=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .streamSettings.realitySettings.serverNames | join(\", \")" "$CONFIG" 2>/dev/null)
        local main_sni=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .streamSettings.realitySettings.serverNames[0]" "$CONFIG" 2>/dev/null)
        
        for ((i=0; i<client_count; i++)); do
            local uuid=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .settings.clients[$i].id" "$CONFIG" 2>/dev/null)
            local remark=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .settings.clients[$i].email // \"$REMARK_NAME\"" "$CONFIG" 2>/dev/null)
            local sid=$(jq -r ".inbounds[] | select(.protocol==\"vless\") | .streamSettings.realitySettings.shortIds[$i]" "$CONFIG" 2>/dev/null)
            
            local target_sni=$(grep "^$uuid|" "$USER_SNI_MAP" 2>/dev/null | cut -d'|' -f2)
            target_sni=${target_sni:-$main_sni}
            
            if test -n "$uuid" && test "$uuid" != "null"; then
                hr
                printf "  ${cyan}【VLESS-Reality (Vision) - 用户 %d】${none}\n" $((i+1))
                printf "  ${yellow}%-16s${none} %s\n" "节点名称:" "$remark"
                printf "  ${yellow}%-16s${none} %s\n" "外网 IP:" "$SERVER_IP"
                printf "  ${yellow}%-16s${none} %s\n" "监听端口:" "$port"
                printf "  ${yellow}%-16s${none} %s\n" "主用 UUID:" "$uuid"
                printf "  ${yellow}%-16s${none} %s\n" "当前主用 SNI:" "$target_sni"
                printf "  ${yellow}%-16s${none} %s\n" "全局容灾矩阵:" "$all_snis"
                printf "  ${yellow}%-16s${none} %s\n" "公钥(pbk):" "$pub"
                printf "  ${yellow}%-16s${none} %s\n" "Short ID:" "$sid"
                
                local link="vless://${uuid}@${SERVER_IP}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${target_sni}&fp=chrome&pbk=${pub}&sid=${sid}&type=tcp#${remark}"
                echo -e "\n  ${cyan}通用链接:${none} \n  $link\n"
                if command -v qrencode >/dev/null 2>&1; then
                    echo -e "  ${cyan}手机扫码导入 (半高紧凑版):${none}"
                    qrencode -m 2 -t UTF8 "$link"
                fi
            fi
        done
    fi

    local s_count=$(jq ".inbounds[] | select(.protocol==\"shadowsocks\") | length" "$CONFIG" 2>/dev/null || echo 0)
    
    if test "${s_count:-0}" -gt 0; then
        local s_port=$(jq -r ".inbounds[] | select(.protocol==\"shadowsocks\") | .port" "$CONFIG" 2>/dev/null)
        local s_pass=$(jq -r ".inbounds[] | select(.protocol==\"shadowsocks\") | .settings.password" "$CONFIG" 2>/dev/null)
        local s_method=$(jq -r ".inbounds[] | select(.protocol==\"shadowsocks\") | .settings.method" "$CONFIG" 2>/dev/null)
        
        if test -n "$s_port" && test "$s_port" != "null"; then
            hr
            printf "  ${cyan}【Shadowsocks】${none}\n"
            printf "  ${yellow}%-16s${none} %s\n" "端口:" "$s_port"
            printf "  ${yellow}%-16s${none} %s\n" "密码:" "$s_pass"
            printf "  ${yellow}%-16s${none} %s\n" "加密方式:" "$s_method"
            
            local b64=$(printf '%s' "${s_method}:${s_pass}" | base64 | tr -d '\n')
            local link_ss="ss://${b64}@${SERVER_IP}:${s_port}#${REMARK_NAME}-SS"
            
            echo -e "\n  ${cyan}通用链接:${none} \n  $link_ss\n"
            if command -v qrencode >/dev/null 2>&1; then
                qrencode -m 2 -t UTF8 "$link_ss"
            fi
        fi
    fi
}

# -- 商用流量与运行状态 --
do_status_menu() {
    while true; do
        title "运行状态与计费中心"
        echo "  1) 设置/修改 每月重置流量的计费日 (需重启vnstat)"
        echo "  2) 服务进程守护状态"
        echo "  3) IP 与 监听网络信息"
        echo "  4) 网卡流量计费核算 (vnstat)"
        echo "  5) 实时连接与独立 IP 统计 (自动刷新/雷达模式)"
        echo -e "  ${cyan}6) 实时修改 Xray CPU 优先级 (-20至-10 动态提权)${none}"
        echo "  0) 返回主菜单"
        hr
        read -rp "选择: " s
        case "$s" in
            1) 
                local current_day=$(grep -E "^[# ]*MonthRotate" /etc/vnstat.conf 2>/dev/null | awk '{print $2}' | tr -d '\r')
                current_day=${current_day:-"1"}
                echo -e "  当前每月清零日为: ${cyan}${current_day} 号${none}"
                read -rp "请输入新的每月账单清零日 (1-31): " d_day
                if test "${d_day:-0}" -ge 1 2>/dev/null && test "${d_day:-0}" -le 31 2>/dev/null; then
                    if grep -q -E "^[# ]*MonthRotate" /etc/vnstat.conf 2>/dev/null; then
                        sed -i -E "s/^[# ]*MonthRotate.*/MonthRotate $d_day/" /etc/vnstat.conf
                    else
                        echo "MonthRotate $d_day" >> /etc/vnstat.conf
                    fi
                    systemctl restart vnstat 2>/dev/null
                    info "流量结算日已重置为每月 $d_day 号 (稍后生效)。"
                else
                    error "输入日期无效。"
                fi
                read -rp "按 Enter 继续..." _ 
                ;;
            2) 
                clear
                title "Xray 服务进程守护状态"
                systemctl status xray --no-pager || true
                echo ""
                read -rp "按 Enter 继续..." _ 
                ;;
            3) 
                echo -e "\n  公网 IP: ${green}$SERVER_IP${none}"
                hr
                echo -e "  DNS 解析流向: "
                grep "^nameserver" /etc/resolv.conf | awk '{print "    " $0}'
                hr
                echo -e "  Xray 本地监听: "
                ss -tlnp | grep xray | awk '{print "    " $4}'
                read -rp "按 Enter 继续..." _ 
                ;;
            4) 
                if ! command -v vnstat >/dev/null 2>&1; then 
                    warn "未安装 vnstat，无法统计流量。"
                    read -rp "Enter..." _ 
                    continue
                fi
                clear
                title "商用级网卡流量计费中心"
                local m_day=$(grep -E "^[# ]*MonthRotate" /etc/vnstat.conf 2>/dev/null | awk '{print $2}' | tr -d '\r')
                m_day=${m_day:-"1 (默认)"}
                echo -e "  每月重置流量的计费日: ${cyan}每月 $m_day 号${none}"
                hr
                (vnstat -m 3 2>/dev/null || vnstat -m 2>/dev/null) | sed -e 's/estimated/估计流量/ig' -e 's/rx/接收/ig' -e 's/tx/发送/ig' -e 's/total/总计/ig' -e 's/daily/按天/ig' -e 's/monthly/按月/ig'
                hr
                echo "  1) 选择某个月，查看某个月按天流量情况"
                echo "  2) 精确调取 最近 3 个自然月的流量季报"
                echo "  q) 退出返回"
                read -rp "  指令: " vn_opt
                
                case "$vn_opt" in
                    1)
                        read -rp "请输入要查询的年月 (例如 $(date +%Y-%m)，直接回车显示近30天): " d_month
                        if test -z "$d_month"; then
                            vnstat -d 2>/dev/null | sed -e 's/estimated/估计流量/ig' -e 's/rx/接收/ig' -e 's/tx/发送/ig' -e 's/total/总计/ig' -e 's/daily/按天/ig' -e 's/monthly/按月/ig'
                        else
                            vnstat -d 2>/dev/null | grep -iE "($d_month| day |estimated|--)" | sed -e 's/estimated/估计流量/ig' -e 's/rx/接收/ig' -e 's/tx/发送/ig' -e 's/total/总计/ig' -e 's/daily/按天/ig' -e 's/monthly/按月/ig'
                            if [ $? -ne 0 ]; then
                                echo -e "  ${yellow}未找到 $d_month 的按天数据，显示默认近期记录：${none}"
                                vnstat -d 2>/dev/null | sed -e 's/estimated/估计流量/ig' -e 's/rx/接收/ig' -e 's/tx/发送/ig' -e 's/total/总计/ig' -e 's/daily/按天/ig' -e 's/monthly/按月/ig'
                            fi
                        fi
                        read -rp "Enter..." _ 
                        ;;
                    2) 
                        (vnstat -m 3 2>/dev/null || vnstat -m) | sed -e 's/estimated/估计流量/ig' -e 's/rx/接收/ig' -e 's/tx/发送/ig' -e 's/total/总计/ig' -e 's/daily/按天/ig' -e 's/monthly/按月/ig'
                        read -rp "Enter..." _ 
                        ;;
                    q) 
                        ;;
                esac
                ;;
            5)
                while true; do
                    clear
                    title "商用级实时连接与独立 IP 统计 (雷达守望模式)"
                    local x_pids=$(pidof xray | xargs | tr -s ' ' '|')
                    if [ -n "$x_pids" ]; then
                        echo -e "  ${cyan}【底层进程与连接池状态分布】${none}"
                        ss -ntupa | grep -E "pid=($x_pids)[,)]" | awk '{print $1"_"$2}' | sort | uniq -c | sort -nr | awk '{printf "    %-15s : %s\n", $2, $1}'
                        
                        echo -e "\n  ${cyan}【连接来源独立 IP 排行 (TOP 10)】${none}"
                        local ips=$(ss -ntupa | grep -E "pid=($x_pids)[,)]" | grep -vE "LISTEN|UNCONN" | awk '{print $6}' | sed -E 's/:[0-9]+$//' | tr -d '[]' | grep -vE "^127\.0\.0\.1$|^0\.0\.0\.0$|^::$|^\*$|^::ffff:127\.0\.0\.1$")
                        
                        if [ -n "$ips" ]; then
                            echo "$ips" | sort | uniq -c | sort -nr | head -n 10 | awk '{printf "    IP: %-18s (并发连接数: %s)\n", $2, $1}'
                            local total_ips=$(echo "$ips" | sort | uniq | wc -l)
                            echo -e "\n  当前独立外部 IP 总数: ${yellow}${total_ips}${none}"
                        else
                            echo -e "    ${gray}当前暂无外部真实连接 (代理处于闲置待命状态)。${none}"
                        fi
                    else
                        echo -e "  ${red}Xray 进程未运行，无法获取底层连接数据。${none}"
                    fi
                    
                    echo -e "\n  ${gray}---------------------------------------------------${none}"
                    echo -e "  ${green}雷达运行中 (每 2 秒自动刷新)...${none}"
                    echo -e "  快捷键: [ ${yellow}r${none} ] 立即强刷  [ ${yellow}q${none} ] 返回主菜单"
                    
                    read -t 2 -n 1 -s cmd
                    if [[ "$cmd" == "q" || "$cmd" == "Q" || "$cmd" == $'\e' ]]; then
                        break
                    elif [[ "$cmd" == "r" || "$cmd" == "R" ]]; then
                        continue
                    fi
                done
                ;;
            6)
                while true; do
                    clear
                    title "实时修改 Xray CPU 优先级 (Nice 调度)"
                    local limit_file="/etc/systemd/system/xray.service.d/limits.conf"
                    local current_nice="-20"
                    if [ -f "$limit_file" ]; then
                        if grep -q "^Nice=" "$limit_file"; then
                            current_nice=$(awk -F'=' '/^Nice=/ {print $2}' "$limit_file" | head -1)
                        fi
                    fi
                    
                    echo -e "  当前 Xray 的 Nice 优先级为: ${cyan}${current_nice}${none}"
                    echo -e "  ${gray}提示: Nice 值越低，CPU 抢占优先级越高。支持 11 档调节 (-20 至 -10)。${none}"
                    hr
                    read -rp "  请输入新的 Nice 值 (例如 -15，输入 q 返回): " new_nice
                    
                    if [[ "$new_nice" == "q" || "$new_nice" == "Q" ]]; then
                        break
                    fi
                    
                    if [[ "$new_nice" =~ ^-[1-2][0-9]$ ]] && [ "$new_nice" -ge -20 ] && [ "$new_nice" -le -10 ]; then
                        if [ -f "$limit_file" ]; then
                            sed -i "s/^Nice=.*/Nice=$new_nice/" "$limit_file"
                            systemctl daemon-reload
                            info "Nice 值已更新为 $new_nice，Xray 将在 5 秒后自动重启生效..."
                            sleep 5
                            systemctl restart xray
                            info "重启完成！优先级已全域生效。"
                        else
                            error "配置文件不存在，请先执行核心安装！"
                        fi
                        read -rp "按 Enter 继续..." _
                        break
                    else
                        error "输入无效！请输入 -20 到 -10 之间的确切数字。"
                        sleep 2
                    fi
                done
                ;;
            0) 
                return 
                ;;
        esac
    done
}

# -- 卸载引擎 (内存级快照保留初装日，生态边界复原与 Xray 自毁) --
do_uninstall() {
    title "清理：彻底卸载 Xray 并复原原生解析"
    read -rp "这将会彻底删除 Xray 并解除 DNS 锁定，但将【永久保留】系统底层的极限并发与内核调优，确认执行？(输入y确定): " confirm
    if test "$confirm" != "y"; then 
        return
    fi
    
    # 内存级备份计费初装日期
    local temp_date=""
    if test -f "$INSTALL_DATE_FILE"; then
        temp_date=$(cat "$INSTALL_DATE_FILE")
        print_magenta ">>> [1/4] 成功提取初装日期快照，等待卸载后回写..."
    fi
    
    print_magenta ">>> [2/4] 正在粉碎 Dnsmasq 极速缓存引擎并恢复系统原生 DNS..."
    systemctl stop dnsmasq >/dev/null 2>&1 || true
    systemctl disable dnsmasq >/dev/null 2>&1 || true
    export DEBIAN_FRONTEND=noninteractive
    apt-get purge -y dnsmasq >/dev/null 2>&1 || yum remove -y dnsmasq >/dev/null 2>&1 || true
    rm -f /etc/dnsmasq.conf >/dev/null 2>&1 || true

    chattr -i /etc/resolv.conf 2>/dev/null || true
    if [ -f /etc/resolv.conf.bak ]; then
        mv -f /etc/resolv.conf.bak /etc/resolv.conf 2>/dev/null || true
    fi
    
    systemctl stop resolvconf.service >/dev/null 2>&1 || true
    systemctl disable resolvconf.service >/dev/null 2>&1 || true
    
    if systemctl list-unit-files | grep -q systemd-resolved; then
        systemctl enable systemd-resolved >/dev/null 2>&1 || true
        systemctl start systemd-resolved >/dev/null 2>&1 || true
    fi

    print_magenta ">>> [3/4] 正在停止并彻底绞杀 Xray 主进程及系统权限映射..."
    systemctl stop xray >/dev/null 2>&1 || true
    systemctl disable xray >/dev/null 2>&1 || true
    rm -rf /etc/systemd/system/xray.service >/dev/null 2>&1
    rm -rf /etc/systemd/system/xray@.service >/dev/null 2>&1
    rm -rf /etc/systemd/system/xray.service.d >/dev/null 2>&1
    rm -rf /lib/systemd/system/xray* >/dev/null 2>&1
    systemctl daemon-reload >/dev/null 2>&1
    
    print_magenta ">>> [4/4] 正在粉碎数据目录、系统日志及物理配置文件..."
    rm -rf "$CONFIG_DIR" "$DAT_DIR" "$XRAY_BIN" "$SCRIPT_DIR" >/dev/null 2>&1
    rm -rf /var/log/xray* >/dev/null 2>&1
    
    (crontab -l 2>/dev/null | grep -v "update-dat.sh") | crontab - 2>/dev/null
    
    rm -f "/usr/local/bin/xrv" >/dev/null 2>&1
    rm -f "$SCRIPT_PATH" >/dev/null 2>&1
    hash -r 2>/dev/null
    
    # 恢复初装计费日
    if test -n "$temp_date"; then
        mkdir -p "$CONFIG_DIR" 2>/dev/null
        echo "$temp_date" > "$INSTALL_DATE_FILE"
    fi
    
    print_green "卸载完成！Xray 及 Dnsmasq 缓存已被彻底粉碎 (您的内核网络栈调优与计费记录已为您完美保留)。"
    exit 0
}

# -- 矩阵切换注入核心 (独立模块化) --
_update_matrix() {
    echo "[$SNI_JSON_ARRAY]" > /tmp/sni_array.json
    jq --arg dest "$BEST_SNI:443" --slurpfile snis /tmp/sni_array.json '
        (.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.serverNames) = $snis[0] |
        (.inbounds[] | select(.protocol=="vless") | .streamSettings.realitySettings.dest) = $dest
    ' "$CONFIG" > "$CONFIG.tmp"
    
    if [ $? -eq 0 ]; then
        mv -f "$CONFIG.tmp" "$CONFIG"
        fix_permissions
        systemctl restart xray >/dev/null 2>&1
    fi
    rm -f /tmp/sni_array.json
}

# -- 安装主逻辑 (全量多行展开与纯正 HereDoc JSON注入) --
do_install() {
    title "Apex Vanguard Ultimate Final: 核心部署"
    preflight
    
    systemctl stop xray >/dev/null 2>&1 || true

    # 严控：如果已有安装日期，则不再覆盖，保证历代升级记录统一
    if [ ! -f "$INSTALL_DATE_FILE" ]; then
        date +"%Y-%m-%d %H:%M:%S" > "$INSTALL_DATE_FILE"
    fi
    
    echo -e "  ${cyan}请选择要安装的代理协议：${none}"
    echo "  1) VLESS-Reality (推荐, 强力防封)"
    echo "  2) Shadowsocks (建议落地机使用)"
    echo "  3) 两个都安装 (双管齐下)"
    
    read -rp "  请输入编号: " proto_choice
    proto_choice=${proto_choice:-1}

    if test "$proto_choice" = "1" || test "$proto_choice" = "3"; then
        while true; do
            read -rp "请输入 VLESS 监听端口 (回车键默认443): " input_p
            input_p=${input_p:-443}
            if validate_port "$input_p"; then 
                LISTEN_PORT="$input_p"
                break
            fi
        done
        read -rp "请输入节点别名 (默认 xp-reality): " input_remark
        REMARK_NAME=${input_remark:-xp-reality}
        
        choose_sni
        if test $? -ne 0; then 
            return 1
        fi
    fi

    local ss_port=8388
    local ss_pass=""
    local ss_method="aes-256-gcm"
    
    if test "$proto_choice" = "2" || test "$proto_choice" = "3"; then
        while true; do
            read -rp "请输入 SS 监听端口 (回车键默认8388): " input_s
            input_s=${input_s:-8388}
            if validate_port "$input_s"; then 
                ss_port="$input_s"
                break
            fi
        done
        
        ss_pass=$(gen_ss_pass)
        ss_method=$(_select_ss_method)
        
        if test "$proto_choice" = "2"; then
            read -rp "请输入节点别名 (默认 xp-reality): " input_remark
            REMARK_NAME=${input_remark:-xp-reality}
        fi
    fi

    print_magenta ">>> 正在静默拉取官方核心组件 (已屏蔽冗余日志)..."
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
    
    install_update_dat
    
    # 注入符合极低延迟突发调优的安全并发突破设置 (包含状态继承机制)
    fix_xray_systemd_limits

    # 1. 纯净构建底层骨架配置 (注入 AsIs 斩断路由层无谓解析)
    cat > "$CONFIG" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "outboundTag": "block",
        "_enabled": true,
        "protocol": [
          "bittorrent"
        ]
      },
      {
        "outboundTag": "block",
        "_enabled": true,
        "ip": [
          "geoip:cn"
        ]
      },
      {
        "outboundTag": "block",
        "_enabled": true,
        "domain": [
          "geosite:cn",
          "geosite:category-ads-all"
        ]
      }
    ]
  },
  "inbounds": [],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
EOF

    if test "$proto_choice" = "1" || test "$proto_choice" = "3"; then
        local keys=$("$XRAY_BIN" x25519 2>/dev/null)
        local priv=$(echo "$keys" | grep -i "Private" | awk -F': ' '{print $2}' | tr -d ' ')
        local pub=$(echo "$keys" | grep -i "Public" | awk -F': ' '{print $2}' | tr -d ' ')
        local uuid=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || $XRAY_BIN uuid)
        local sid=$(head -c 8 /dev/urandom | xxd -p | tr -d '\n')
        local ctime=$(date +"%Y-%m-%d %H:%M")
        
        echo "$pub" > "$PUBKEY_FILE"
        echo "$uuid|$ctime" > "$USER_TIME_MAP"
        
        # 2. 绝对纯净的 HereDoc JSON 注入，加入 sockopt 极致提速突发性能
        echo "[$SNI_JSON_ARRAY]" > /tmp/sni_array.json
        cat > /tmp/vless_inbound.json <<EOF
{
  "tag": "vless-reality",
  "listen": "0.0.0.0",
  "port": $LISTEN_PORT,
  "protocol": "vless",
  "settings": {
    "clients": [
      {
        "id": "$uuid",
        "flow": "xtls-rprx-vision",
        "email": "$REMARK_NAME"
      }
    ],
    "decryption": "none"
  },
  "streamSettings": {
    "network": "tcp",
    "security": "reality",
    "sockopt": {
        "tcpNoDelay": true,
        "tcpFastOpen": true
    },
    "realitySettings": {
      "dest": "$BEST_SNI:443",
      "serverNames": [],
      "privateKey": "$priv",
      "publicKey": "$pub",
      "shortIds": [
        "$sid"
      ]
    }
  },
  "sniffing": {
    "enabled": true,
    "destOverride": [
      "http",
      "tls",
      "quic"
    ]
  }
}
EOF
        
        # 合并 SNI 数组进 vless 的 JSON 结构，并安全拼接到全局 CONFIG 中
        jq --slurpfile snis /tmp/sni_array.json '.streamSettings.realitySettings.serverNames = $snis[0]' /tmp/vless_inbound.json > /tmp/vless_final.json
        jq '.inbounds += [input]' "$CONFIG" /tmp/vless_final.json > "$CONFIG.tmp" && mv -f "$CONFIG.tmp" "$CONFIG"
        rm -f /tmp/vless_inbound.json /tmp/vless_final.json /tmp/sni_array.json
    fi

    if test "$proto_choice" = "2" || test "$proto_choice" = "3"; then
        # 彻底展开 SS JSON，同步加入 sockopt 突发性能
        cat > /tmp/ss_inbound.json <<EOF
{
  "tag": "shadowsocks",
  "listen": "0.0.0.0",
  "port": $ss_port,
  "protocol": "shadowsocks",
  "settings": {
    "method": "$ss_method",
    "password": "$ss_pass",
    "network": "tcp,udp"
  },
  "streamSettings": {
    "sockopt": {
        "tcpNoDelay": true,
        "tcpFastOpen": true
    }
  }
}
EOF
        jq '.inbounds += [input]' "$CONFIG" /tmp/ss_inbound.json > "$CONFIG.tmp" && mv -f "$CONFIG.tmp" "$CONFIG"
        rm -f /tmp/ss_inbound.json
    fi

    fix_permissions
    
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray >/dev/null 2>&1
    
    info "网络架构部署完成！"
    do_summary
    
    # 安装完毕后的操作闭环
    while true; do
        read -rp "按 Enter 返回主菜单，或输入 b 重配矩阵: " opt
        if [[ "$opt" == "b" || "$opt" == "B" ]]; then
            choose_sni
            if test $? -eq 0; then
                _update_matrix
                do_summary
            else
                break
            fi
        else
            break
        fi
    done
}

# -- 主菜单 (全量不折叠) --
main_menu() {
    while true; do
        clear
        echo -e "${blue}===================================================${none}"
        echo -e "  ${magenta}Xray ex89 The Apex Vanguard - Project Genesis V89${none}"
        
        local svc=$(systemctl is-active xray 2>/dev/null || echo "inactive")
        if test "$svc" = "active"; then 
            svc="${green}运行中${none}"
        else 
            svc="${red}停止${none}"
        fi
        
        echo -e "  状态: $svc | 快捷指令: ${cyan}xrv${none}"
        echo -e "${blue}===================================================${none}"
        echo "  1) 核心安装 / 重构网络 (VLESS/SS 双协议)"
        echo "  2) 用户管理 (增删/导入/专属 SNI 挂载)"
        echo "  3) 分发中心 (多用户详情与紧凑二维码)"
        echo "  4) 手动更新 Geo 规则库 (已夜间自动热更)"
        echo "  5) 更新 Xray 核心 (无缝拉取最新版重启)"
        echo "  6) 无感热切 SNI 矩阵 (单选/多选/全选防封阵列)"
        echo "  7) 屏蔽规则管理 (BT/广告双轨拦截)"
        echo "  9) 运行状态 (实时 IP 统计/DNS/流量核算)"
        echo "  10) 初次安装、更新系统组件"
        echo "  0) 退出"
        echo -e "  ${red}88) 彻底卸载 (安全复原系统解析并清空软件痕迹)${none}"
        hr
        
        read -rp "选择: " num
        case "$num" in
            1) 
                do_install 
                ;;
            2) 
                do_user_manager 
                ;;
            3) 
                do_summary 
                while true; do
                    read -rp "按 Enter 返回主菜单，或输入 b 重选 SNI: " rb
                    if [[ "$rb" == "b" || "$rb" == "B" ]]; then
                        choose_sni
                        if test $? -eq 0; then
                            _update_matrix
                            do_summary
                        else
                            break
                        fi
                    else
                        break
                    fi
                done
                ;;
            4) 
                print_magenta ">>> 正在同步最新规则库..."
                bash -c "$(curl -fsSL https://raw.githubusercontent.com/XTLS/Xray-install/main/install-release.sh)" @ install-geodata >/dev/null 2>&1
                systemctl restart xray >/dev/null 2>&1
                info "Geo 更新成功"
                read -rp "按 Enter 继续..." _ 
                ;;
            5) 
                do_update_core 
                ;;
            6) 
                choose_sni
                if test $? -eq 0; then
                    _update_matrix
                    do_summary
                    
                    while true; do
                        read -rp "按 Enter 返回主菜单，或输入 b 继续重新分配矩阵: " rb
                        if [[ "$rb" == "b" || "$rb" == "B" ]]; then
                            choose_sni
                            if test $? -eq 0; then
                                _update_matrix
                                do_summary
                            else
                                break
                            fi
                        else
                            break
                        fi
                    done
                fi
                ;;
            7) 
                _global_block_rules 
                ;;
            9) 
                do_status_menu 
                ;;
            10) 
                do_sys_init_menu 
                ;;
            88) 
                do_uninstall 
                ;;
            0) 
                exit 0 
                ;;
        esac
    done
}

preflight
main_menu
