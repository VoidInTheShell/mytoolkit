#!/bin/sh
# irq-tuner watchdog - Monitor and auto-fix RSS configuration
# This script runs periodically (typically every 5 minutes via cron)
# to check RSS health and automatically reapply tuning if needed

set -u

CONFIG_FILE="/etc/irq-tuner/irq-tuner.conf"

# Load configuration
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
fi

ENABLE="${ENABLE:-1}"
RPS_ENABLE="${RPS_ENABLE:-1}"
IFACES="${IFACES:-}"
RPS_CPUS="${RPS_CPUS:-f}"
[ "$ENABLE" -eq 1 ] || exit 0

# Check if RSS configuration is healthy
check_rss_health() {
  iface="$1"

  # Check 1: rps_flow_cnt should not be 0 if RPS is enabled
  for path in /sys/class/net/"$iface"/queues/rx-*/rps_flow_cnt; do
    [ -r "$path" ] || continue
    val=$(cat "$path" 2>/dev/null)
    if [ "$val" = "0" ] && [ "$RPS_ENABLE" -eq 1 ]; then
      logger -t irq-tuner-watchdog -p daemon.warning "$iface rps_flow_cnt=0, needs fix"
      return 1
    fi
  done

  # Check 2: rps_cpus should match configured mask (not overwritten by autocore)
  if [ "$RPS_ENABLE" -eq 1 ]; then
    for path in /sys/class/net/"$iface"/queues/rx-*/rps_cpus; do
      [ -r "$path" ] || continue
      val=$(cat "$path" 2>/dev/null)
      if [ "$val" != "$RPS_CPUS" ]; then
        logger -t irq-tuner-watchdog -p daemon.warning "$iface rps_cpus=$val (expected $RPS_CPUS), needs fix"
        return 1
      fi
    done
  fi

  # Check 3: IRQ distribution should not be severely imbalanced
  # Read interrupt counts for all fastpath IRQs
  irqs=$(grep "${iface}-fp-" /proc/interrupts 2>/dev/null | awk '{gsub(":","",$1); print $1}')
  if [ -z "$irqs" ]; then
    # No MSI-X interrupts found, skip this check
    return 0
  fi

  max_count=0
  min_count=999999999
  for irq in $irqs; do
    # Sum interrupt counts across all CPUs for this IRQ
    count=$(awk -v irq="$irq:" '$1 == irq {
      sum=0;
      for(i=2;i<=NF;i++) {
        if($i ~ /^[0-9]+$/) sum+=$i
      }
      print sum;
      exit
    }' /proc/interrupts)

    [ -n "$count" ] || continue
    [ "$count" -gt "$max_count" ] && max_count=$count
    [ "$count" -lt "$min_count" ] && min_count=$count
  done

  # If max/min ratio exceeds 10:1, consider it imbalanced
  if [ "$max_count" -gt 0 ] && [ "$min_count" -gt 0 ]; then
    ratio=$((max_count / min_count))
    if [ "$ratio" -gt 10 ]; then
      logger -t irq-tuner-watchdog -p daemon.warning "$iface IRQ imbalance detected (ratio=$ratio), needs fix"
      return 1
    fi
  fi

  return 0
}

# Main loop - check all configured interfaces
for iface in ${IFACES:-}; do
  [ -d "/sys/class/net/$iface" ] || continue

  if ! check_rss_health "$iface"; then
    logger -t irq-tuner-watchdog -p daemon.notice "Applying fix for $iface"
    /usr/sbin/irq-tuner apply --iface "$iface" --quiet
    if [ $? -eq 0 ]; then
      logger -t irq-tuner-watchdog -p daemon.info "$iface tuning reapplied successfully"
    else
      logger -t irq-tuner-watchdog -p daemon.err "$iface tuning failed to reapply"
    fi
  fi
done
