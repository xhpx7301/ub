# Ubuntu 桌面/服务器模式切换器

`ubuntu-mode-switcher.sh` 使用 systemd 的启动目标在图形桌面和无图形服务器之间切换，适合长期运行 Emby 等服务的旧笔记本。

## 安装与使用

```bash
chmod +x ubuntu-mode-switcher.sh
sudo apt install zenity                 # 只在需要图形界面时安装
./ubuntu-mode-switcher.sh                # 打开图形菜单
./ubuntu-mode-switcher.sh --status       # 查看状态
./ubuntu-mode-switcher.sh --server       # 设置下次启动为服务器模式
./ubuntu-mode-switcher.sh --desktop      # 设置下次启动为桌面模式
sudo ./ubuntu-mode-switcher.sh --server --now
```

普通用户运行时，脚本会通过 `sudo` 请求权限。默认操作只执行 `systemctl set-default`，当前桌面会话保持不变；带 `--now` 才会执行 `systemctl isolate`，这可能关闭当前图形会话。服务器模式下重启即可让电脑不启动桌面显示管理器，从而减少内存和功耗。

脚本不会猜测或停止 Emby 服务。若你的旧方案还需要切换特定服务，请在脚本中的 `desktop_enter_hook` 和 `server_enter_hook` 函数里加入对应的 `systemctl` 命令。

## 常用回滚命令

```bash
sudo systemctl set-default graphical.target   # 恢复桌面默认启动
sudo systemctl set-default multi-user.target  # 恢复服务器默认启动
```
