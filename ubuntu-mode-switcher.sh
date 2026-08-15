#!/usr/bin/env bash
set -Eeuo pipefail

# Switch the systemd boot target between a graphical desktop and a headless server.
# Keep site-specific service commands in the optional hook functions below.

APP_NAME="Ubuntu 模式切换"
DESKTOP_TARGET="graphical.target"
SERVER_TARGET="multi-user.target"

usage() {
    cat <<'EOF'
用法:
  ubuntu-mode-switcher.sh                 打开图形界面（需要 Zenity）
  ubuntu-mode-switcher.sh --status        显示当前和下次启动模式
  ubuntu-mode-switcher.sh --desktop       设置下次启动进入桌面模式
  ubuntu-mode-switcher.sh --server        设置下次启动进入服务器模式
  ubuntu-mode-switcher.sh --desktop --now 设置桌面模式并立即切换（会结束图形会话）
  ubuntu-mode-switcher.sh --server --now  设置服务器模式并立即切换（会结束图形会话）
  ubuntu-mode-switcher.sh --reboot        重启电脑

默认只修改下次启动目标。--now 会执行 systemctl isolate，请先保存工作。
EOF
}

die() { printf '错误: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || SUDO=(sudo) || SUDO=()
command_exists() { command -v "$1" >/dev/null 2>&1; }

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

require_systemd() {
    command_exists systemctl || die "找不到 systemctl；此工具需要 systemd。"
    systemctl is-system-running >/dev/null 2>&1 || true
}

get_default_target() {
    run_privileged systemctl get-default 2>/dev/null || printf '未知'
}

get_active_target() {
    if run_privileged systemctl is-active --quiet graphical.target; then
        printf '%s' "$DESKTOP_TARGET"
    elif run_privileged systemctl is-active --quiet multi-user.target; then
        printf '%s' "$SERVER_TARGET"
    else
        printf '未知'
    fi
}

target_label() {
    case "$1" in
        "$DESKTOP_TARGET") printf '桌面模式（图形界面）' ;;
        "$SERVER_TARGET") printf '服务器模式（无图形界面）' ;;
        *) printf '%s' "$1" ;;
    esac
}

print_status() {
    require_systemd
    local default active
    default=$(get_default_target)
    active=$(get_active_target)
    printf '当前运行模式: %s\n' "$(target_label "$active")"
    printf '下次启动模式: %s\n' "$(target_label "$default")"
}

# Optional hooks for machine-specific services. They are intentionally empty so
# the script never guesses which Emby or desktop services should be stopped.
desktop_enter_hook() { :; }
server_enter_hook() { :; }

apply_mode() {
    local mode="$1" now="${2:-false}" target label
    case "$mode" in
        desktop) target="$DESKTOP_TARGET"; label='桌面模式（图形界面）' ;;
        server) target="$SERVER_TARGET"; label='服务器模式（无图形界面）' ;;
        *) die "未知模式: $mode" ;;
    esac

    require_systemd
    local current
    current=$(get_default_target)
    if [[ "$current" != "$target" ]]; then
        run_privileged systemctl set-default "$target"
        printf '已设置下次启动为: %s\n' "$label"
    else
        printf '下次启动已经是: %s\n' "$label"
    fi

    if [[ "$mode" == desktop ]]; then desktop_enter_hook; else server_enter_hook; fi

    if [[ "$now" == true ]]; then
        printf '正在立即切换到 %s；当前图形会话可能会结束。\n' "$label"
        run_privileged systemctl isolate "$target"
    else
        printf '当前会话未改变。需要重启后生效。\n'
    fi
}

reboot_system() {
    require_systemd
    run_privileged systemctl reboot
}

confirm_gui() {
    local text="$1"
    zenity --question --title="$APP_NAME" --width=460 --text="$text" --ok-label='继续' --cancel-label='取消'
}

gui() {
    command_exists zenity || die "未安装 Zenity。可运行: sudo apt install zenity"
    require_systemd
    while true; do
        local default active choice
        default=$(get_default_target)
        active=$(get_active_target)
        choice=$(zenity --list --title="$APP_NAME" --width=620 --height=390 \
            --text="当前运行: $(target_label "$active")\n下次启动: $(target_label "$default")\n\n选择要执行的操作" \
            --column='操作' --column='说明' \
            'desktop' '设置桌面模式（下次启动）' \
            'server' '设置服务器模式（下次启动）' \
            'desktop-now' '立即切换到桌面模式' \
            'server-now' '立即切换到服务器模式' \
            'reboot' '重启电脑并应用下次启动模式' \
            'status' '在终端显示详细状态' \
            --print-column=1 --hide-column=1 --ok-label='执行' --cancel-label='退出') || return 0

        case "$choice" in
            desktop|server)
                confirm_gui "确认设置为$(target_label "${choice/desktop/$DESKTOP_TARGET}")？\n当前会话不会改变。" || continue
                apply_mode "$choice"
                zenity --info --title="$APP_NAME" --text='设置已完成。重启后生效。' --ok-label='确定' ;;
            desktop-now|server-now)
                local mode=${choice%-now}
                confirm_gui "确认立即切换到$(target_label "${mode/desktop/$DESKTOP_TARGET}")？\n当前图形会话可能会结束，请先保存工作。" || continue
                apply_mode "$mode" true
                zenity --info --title="$APP_NAME" --text='切换命令已发送。' --ok-label='确定' || true
                return 0 ;;
            reboot)
                confirm_gui '确认现在重启电脑？未保存的工作将丢失。' || continue
                reboot_system; return 0 ;;
            status)
                print_status | zenity --text-info --title="$APP_NAME - 状态" --width=520 --height=220 --ok-label='关闭' ;;
        esac
    done
}

main() {
    local mode='' now=false
    while (($#)); do
        case "$1" in
            --desktop) mode=desktop ;;
            --server) mode=server ;;
            --now) now=true ;;
            --status) print_status; return ;;
            --reboot) reboot_system; return ;;
            -h|--help) usage; return ;;
            *) usage >&2; die "未知参数: $1" ;;
        esac
        shift
    done
    if [[ -n "$mode" ]]; then apply_mode "$mode" "$now"; else gui; fi
}

main "$@"
