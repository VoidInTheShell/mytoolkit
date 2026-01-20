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

/usr/sbin/irq-tuner init

/etc/init.d/irq-tuner enable

printf "现在进入交互配置? [y/N]: "
read -r ans
case "$ans" in
  y|Y) /usr/sbin/irq-tuner configure ;;
esac

/usr/sbin/irq-tuner status
printf "现在应用调优? [y/N]: "
read -r ans
case "$ans" in
  y|Y) /usr/sbin/irq-tuner apply --with-detect ;;
esac

echo "安装完成. 使用: irq-tuner"
