#!/bin/sh

set -eu

if [ "$(id -u)" -ne 0 ]; then
  echo "请以 root 身份运行."
  exit 1
fi

if [ -x /usr/sbin/irq-tuner ]; then
  /usr/sbin/irq-tuner uninstall
  exit 0
fi

CONFIG_DIR="/etc/irq-tuner"
STATE_DIR="$CONFIG_DIR/state.d"

set_sysctl() {
  key="$1"
  val="$2"
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -w "$key=$val" >/dev/null 2>&1 && return 0
  fi
  path="/proc/sys/$(echo "$key" | tr '.' '/')"
  [ -w "$path" ] && echo "$val" > "$path"
}

if [ -f "$STATE_DIR/sysctl_rps_sock_flow_entries" ]; then
  val="$(cat "$STATE_DIR/sysctl_rps_sock_flow_entries" 2>/dev/null)"
  [ -n "$val" ] && set_sysctl net.core.rps_sock_flow_entries "$val"
fi

if [ -f "$STATE_DIR/baseline.env" ]; then
  while IFS='=' read -r key val; do
    case "$key" in
      COMBINED_*)
        iface="${key#COMBINED_}"
        if command -v ethtool >/dev/null 2>&1; then
          ethtool -L "$iface" combined "$val" >/dev/null 2>&1
        fi
        ;;
    esac
  done < "$STATE_DIR/baseline.env"
fi

if [ -f "$STATE_DIR/restore.list" ]; then
  while IFS='=' read -r path val; do
    [ -n "$path" ] || continue
    [ -w "$path" ] || continue
    echo "$val" > "$path" 2>/dev/null
  done < "$STATE_DIR/restore.list"
fi

if [ -x /etc/init.d/irq-tuner ]; then
  /etc/init.d/irq-tuner stop >/dev/null 2>&1
  /etc/init.d/irq-tuner disable >/dev/null 2>&1
fi

rm -f /etc/init.d/irq-tuner \
      /etc/hotplug.d/iface/99-irq-tuner \
      /etc/sysctl.d/99-irq-tuner.conf \
      /usr/sbin/irq-tuner

rm -rf "$CONFIG_DIR"

echo "已卸载 irq-tuner."
