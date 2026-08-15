# Ubuntu 桌面/服务器模式切换器

`ubuntu-mode-switcher.sh` 使用 systemd 的启动目标在图形桌面和无图形服务器之间切换，适合长期运行 Emby 等服务的旧笔记本。

## 安装与使用

```bash
chmod +x ubuntu-mode-switcher.sh
chmod +x ub
sudo apt install zenity                 # 只在需要图形界面时安装
./ubuntu-mode-switcher.sh                # 有桌面时打开图形菜单，否则打开终端菜单
./ub                                    # 快捷菜单入口
./ubuntu-mode-switcher.sh --status       # 查看状态
./ubuntu-mode-switcher.sh --update       # 检查并更新脚本
sudo ./ubuntu-mode-switcher.sh --server --now
```

普通用户从终端运行时，脚本会通过 `sudo` 请求权限；从 Zenity 图形界面运行时，则优先弹出系统的 PolicyKit 授权窗口。桌面/服务器菜单操作会立即执行 `systemctl isolate`，并同步设置默认启动目标，使重启后继续保持所选模式。立即切换可能关闭当前图形会话。

脚本不会猜测或停止 Emby 服务。若你的旧方案还需要切换特定服务，请在脚本中的 `desktop_enter_hook` 和 `server_enter_hook` 函数里加入对应的命令；需要权限时请用 `run_privileged systemctl ...`。

## 服务器模式下切换回桌面

服务器模式没有图形界面时，可以通过 SSH 登录笔记本执行：

```bash
ssh 用户名@笔记本IP
ub
# 选择 1：立即切换到桌面模式
```

终端菜单中的切换和重启操作使用 `[Y/n]`：直接回车或输入 `y` 执行，输入 `n` 取消。

## 安装 `ub` 快捷命令

如果希望在任意目录直接输入 `ub`，建议让 PATH 中的入口指向 Git 仓库，这样菜单里的更新功能才能更新当前正在使用的脚本：

```bash
mkdir -p "$HOME/.local/bin"
chmod +x "$HOME/ub/ubuntu-mode-switcher.sh" "$HOME/ub/ub"
ln -sfn "$HOME/ub/ubuntu-mode-switcher.sh" "$HOME/.local/bin/ubuntu-mode-switcher.sh"
ln -sfn "$HOME/ub/ub" "$HOME/.local/bin/ub"
export PATH="$HOME/.local/bin:$PATH"
```

然后执行 `ub` 即可打开快捷菜单。将 PATH 配置加入 `~/.bashrc` 后，重新登录仍然有效。若之前把副本安装到了 `/usr/local/bin`，请先移除或替换旧副本，避免执行到旧版本。

更新功能只接受 `git pull --ff-only`，发现本地未提交修改时会停止更新，不会覆盖本地文件。

## 常用回滚命令

```bash
sudo systemctl set-default graphical.target   # 恢复桌面默认启动
sudo systemctl set-default multi-user.target  # 恢复服务器默认启动
```
