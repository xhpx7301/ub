#!/usr/bin/env bash
set -Eeuo pipefail

# Switch the systemd boot target between a graphical desktop and a headless server.
# Keep site-specific service commands in the optional hook functions below.

APP_NAME="Ubuntu 模式切换"
DESKTOP_TARGET="graphical.target"
SERVER_TARGET="multi-user.target"
GUI_MODE=false
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
用法:
  ubuntu-mode-switcher.sh                 打开图形界面（需要 Zenity）
  ubuntu-mode-switcher.sh --status        显示当前和重启后默认模式
  ubuntu-mode-switcher.sh --desktop --now 设置桌面模式并立即切换（会结束图形会话）
  ubuntu-mode-switcher.sh --server --now  设置服务器模式并立即切换（会结束图形会话）
  ubuntu-mode-switcher.sh --reboot        重启电脑
  ubuntu-mode-switcher.sh --menu         打开终端快捷菜单

立即切换会同步设置默认启动目标，使重启后保持所选模式。
EOF
}

show_error() {
    local message="$*"
    if [[ "$GUI_MODE" == true ]] && command_exists zenity; then
        zenity --error --title="$APP_NAME" --width=520 --text="$message" --ok-label='关闭' || true
    else
        printf '错误: %s\n' "$message" >&2
    fi
}

die() { show_error "$*"; exit 1; }

on_error() {
    local exit_code=$? line="$1" command="$2"
    show_error "命令执行失败（第 ${line} 行）:\n${command}"
    exit "$exit_code"
}

trap 'on_error "$LINENO" "$BASH_COMMAND"' ERR

command_exists() { command -v "$1" >/dev/null 2>&1; }

run_privileged() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif [[ -t 0 || -t 1 ]]; then
        sudo "$@"
    elif command_exists pkexec; then
        # Zenity has no terminal for a sudo password prompt. pkexec opens the
        # desktop's normal PolicyKit authentication dialog instead.
        local executable
        executable=$(command -v "$1") || die "找不到命令: $1"
        pkexec "$executable" "${@:2}"
    else
        sudo "$@"
    fi
}

require_systemd() {
    command_exists systemctl || die "找不到 systemctl；此工具需要 systemd。"
}

get_default_target() {
    systemctl get-default 2>/dev/null || printf '未知'
}

get_active_target() {
    if systemctl is-active --quiet graphical.target; then
        printf '%s' "$DESKTOP_TARGET"
    elif systemctl is-active --quiet multi-user.target; then
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

mode_target() {
    case "$1" in
        desktop) printf '%s' "$DESKTOP_TARGET" ;;
        server) printf '%s' "$SERVER_TARGET" ;;
        *) printf '%s' "$1" ;;
    esac
}

print_status() {
    require_systemd
    local default active
    default=$(get_default_target)
    active=$(get_active_target)
    printf '当前运行模式: %s\n' "$(target_label "$active")"
    printf '重启后默认模式: %s\n' "$(target_label "$default")"
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
        printf '已设定重启后默认模式: %s\n' "$label"
    else
        printf '重启后默认模式已经是: %s\n' "$label"
    fi

    if [[ "$mode" == desktop ]]; then desktop_enter_hook; else server_enter_hook; fi

    if [[ "$now" == true ]]; then
        printf '正在立即切换到 %s；当前图形会话可能会结束。\n' "$label"
        run_privileged systemctl isolate "$target"
    else
        printf '当前会话未改变。\n'
    fi
}

reboot_system() {
    require_systemd
    run_privileged systemctl reboot
}

confirm_update() {
    if [[ "$GUI_MODE" == true ]]; then
        zenity --question --title="$APP_NAME" --width=520 \
            --text="$1" --ok-label='更新' --cancel-label='取消'
    else
        confirm_terminal "$1"
    fi
}

update_script() {
    command_exists git || die '未安装 Git。可运行: sudo apt install git'
    local repo upstream status commits
    repo=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) \
        || die "脚本目录不是 Git 仓库，无法自动更新。请从 Git 仓库目录运行 ub。"

    status=$(git -C "$repo" status --porcelain --untracked-files=normal)
    [[ -z "$status" ]] || die "Git 仓库存在未提交修改，已停止更新。请先处理:\n$status"

    printf '正在检查更新...\n'
    git -C "$repo" fetch --prune origin
    upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) \
        || die '当前分支没有远程跟踪分支，无法自动更新。'
    commits=$(git -C "$repo" log --oneline "HEAD..$upstream")
    if [[ -z "$commits" ]]; then
        printf '当前已经是最新版本。\n'
        return 0
    fi

    printf '可更新内容:\n%s\n' "$commits"
    confirm_update '发现新版本，确认更新脚本？' || {
        printf '已取消更新。\n'
        return 0
    }
    git -C "$repo" pull --ff-only
    printf '更新完成。下次执行 ub 时生效。\n'
}

pause_terminal() {
    local ignored
    read -r -p '按回车返回菜单...' ignored || true
}

confirm_terminal() {
    local answer
    read -r -p "$1 [Y/n] " answer || return 1
    case "${answer:-y}" in
        y|Y) return 0 ;;
        n|N) return 1 ;;
        *) printf '请输入 y 或 n。\n'; return 1 ;;
    esac
}

terminal_menu() {
    command_exists systemctl || die '找不到 systemctl；此工具需要 systemd。'
    while true; do
        local default active choice
        default=$(get_default_target)
        active=$(get_active_target)
        printf '\n=== %s ===\n' "$APP_NAME"
        printf '当前运行: %s\n' "$(target_label "$active")"
        printf '重启后默认模式: %s\n\n' "$(target_label "$default")"
        printf '%s\n' \
            '1) 立即切换到桌面模式' \
            '2) 立即切换到服务器模式' \
            '3) 重启电脑' \
            '4) 查看详细状态' \
            '5) 检查并更新脚本' \
            '0) 退出'
        if ! read -r -p '请选择操作 [0-5]: ' choice; then
            printf '\n'
            return 0
        fi
        case "$choice" in
            1)
                if confirm_terminal '立即切换到桌面模式会结束当前会话。'; then
                    apply_mode desktop true
                    return 0
                fi
                ;;
            2)
                if confirm_terminal '立即切换到服务器模式会结束当前会话。'; then
                    apply_mode server true
                    return 0
                fi
                ;;
            3)
                if confirm_terminal '确认重启电脑？'; then
                    reboot_system
                fi
                ;;
            4) print_status; pause_terminal ;;
            5) update_script; pause_terminal ;;
            0) return 0 ;;
            *) printf '无效选择，请重试。\n' ;;
        esac
    done
}

confirm_gui() {
    local text="$1"
    zenity --question --title="$APP_NAME" --width=460 --text="$text" --ok-label='继续' --cancel-label='取消'
}

gui() {
    GUI_MODE=true
    command_exists zenity || die "未安装 Zenity。可运行: sudo apt install zenity"
    require_systemd
    while true; do
        local default active choice
        default=$(get_default_target)
        active=$(get_active_target)
        choice=$(zenity --list --title="$APP_NAME" --width=620 --height=390 \
            --text="当前运行: $(target_label "$active")\n重启后默认模式: $(target_label "$default")\n\n选择要执行的操作" \
            --column='操作' --column='说明' \
            'desktop' '立即切换到桌面模式' \
            'server' '立即切换到服务器模式' \
            'reboot' '重启电脑' \
            'status' '查看详细状态' \
            'update' '检查并更新脚本' \
            'exit' '退出' \
            --print-column=1 --hide-column=1 --ok-label='执行' --cancel-label='退出') || return 0

        case "$choice" in
            desktop|server)
                confirm_gui "确认立即切换到$(target_label "$(mode_target "$choice")")？\n当前图形会话可能会结束，请先保存工作。" || continue
                apply_mode "$choice" true
                zenity --info --title="$APP_NAME" --text='切换命令已发送。' --ok-label='确定' || true
                return 0 ;;
            reboot)
                confirm_gui '确认现在重启电脑？未保存的工作将丢失。' || continue
                reboot_system; return 0 ;;
            status)
                print_status | zenity --text-info --title="$APP_NAME - 状态" --width=520 --height=220 --ok-label='关闭' || true ;;
            update)
                update_script | zenity --text-info --title="$APP_NAME - 更新" --width=620 --height=320 --ok-label='关闭' || true ;;
            exit) return 0 ;;
        esac
    done
}

main() {
    local mode='' action='' now=false
    while (($#)); do
        case "$1" in
            --desktop|--server)
                [[ -z "$mode" ]] || die "--desktop 和 --server 不能同时使用。"
                [[ -z "$action" ]] || die "模式参数不能和其他操作同时使用。"
                mode="${1#--}" ;;
            --now) now=true ;;
            --menu)
                [[ -z "$mode" && -z "$action" ]] || die "--menu 不能和其他操作同时使用。"
                action=menu ;;
            --status|--reboot|--update)
                [[ -z "$mode" && -z "$action" ]] || die "$1 不能和模式或其他操作同时使用。"
                action="${1#--}" ;;
            -h|--help) usage; return ;;
            *) usage >&2; die "未知参数: $1" ;;
        esac
        shift
    done
    [[ "$now" == false || -n "$mode" ]] || die "--now 必须和 --desktop 或 --server 一起使用。"
    [[ -z "$mode" || "$now" == true ]] || die "桌面/服务器模式必须和 --now 一起使用。"

    case "$action" in
        status) print_status ;;
        reboot) reboot_system ;;
        update) update_script ;;
        menu) terminal_menu ;;
        '')
            if [[ -n "$mode" ]]; then
                apply_mode "$mode" "$now"
            elif [[ -n "${DISPLAY:-}" ]] && command_exists zenity; then
                gui
            else
                terminal_menu
            fi ;;
    esac
}

main "$@"
