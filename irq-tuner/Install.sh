#!/bin/sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 身份运行."
  exit 1
fi

BASE_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
MAIN="$BASE_DIR/irq-tuner"
INIT="$BASE_DIR/irq-tuner.init"
HOTPLUG="$BASE_DIR/irq-tuner.hotplug"
WATCHDOG="$BASE_DIR/irq-tuner-watchdog.sh"

for f in "$MAIN" "$INIT" "$HOTPLUG"; do
  if [ ! -f "$f" ]; then
    echo "缺少文件: $f"
    exit 1
  fi
done

mkdir -p /usr/sbin /etc/init.d /etc/hotplug.d/iface

cp "$MAIN" /usr/sbin/irq-tuner
chmod 0755 /usr/sbin/irq-tuner

cp "$INIT" /etc/init.d/irq-tuner
chmod 0755 /etc/init.d/irq-tuner

cp "$HOTPLUG" /etc/hotplug.d/iface/99-irq-tuner
chmod 0755 /etc/hotplug.d/iface/99-irq-tuner

# Install watchdog if available
if [ -f "$WATCHDOG" ]; then
  cp "$WATCHDOG" /usr/sbin/irq-tuner-watchdog
  chmod 0755 /usr/sbin/irq-tuner-watchdog
  echo "Watchdog脚本已安装"
fi

/usr/sbin/irq-tuner init

/etc/init.d/irq-tuner enable

printf "现在进入交互配置? [y/N]: "
read -r ans
case "$ans" in
  y|Y) /usr/sbin/irq-tuner configure ;;
esac

/usr/sbin/irq-tuner status

# Ask about enabling watchdog
if [ -f /usr/sbin/irq-tuner-watchdog ]; then
  printf "启用watchdog定期检查（每5分钟）? [y/N]: "
  read -r ans
  case "$ans" in
    y|Y)
      if command -v crontab >/dev/null 2>&1; then
        (crontab -l 2>/dev/null | grep -v irq-tuner-watchdog; \
         echo "*/5 * * * * /usr/sbin/irq-tuner-watchdog") | crontab -
        echo "Watchdog已启用（每5分钟检查一次）"
      else
        echo "警告: 未找到crontab命令，无法启用watchdog"
      fi
      ;;
  esac
fi

printf "现在应用调优? [y/N]: "
read -r ans
case "$ans" in
  y|Y) /usr/sbin/irq-tuner apply --with-detect ;;
esac

echo "安装完成. 使用: irq-tuner"
