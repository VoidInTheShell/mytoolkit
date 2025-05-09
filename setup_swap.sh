#!/bin/bash

set -e

SWAPFILE="/swapfile"

# 获取总内存大小（MB）
TOTAL_MEM_MB=$(grep MemTotal /proc/meminfo | awk '{print int($2 / 1024)}')

# 推荐 swap 大小算法
if [ "$TOTAL_MEM_MB" -le 2048 ]; then
    RECOMMENDED_SWAP_MB=$((TOTAL_MEM_MB * 2))
elif [ "$TOTAL_MEM_MB" -le 8192 ]; then
    RECOMMENDED_SWAP_MB=$((TOTAL_MEM_MB))
else
    RECOMMENDED_SWAP_MB=$((TOTAL_MEM_MB / 2))
    # 最小 2048MB
    if [ "$RECOMMENDED_SWAP_MB" -lt 2048 ]; then
        RECOMMENDED_SWAP_MB=2048
    fi
fi

echo "检测到系统总内存为 ${TOTAL_MEM_MB} MB。"
echo "推荐的 Swap 大小为 ${RECOMMENDED_SWAP_MB} MB。"

read -p "请输入 Swap 大小 (MB)，直接回车使用推荐值: " USER_SWAP_MB
if [[ -z "$USER_SWAP_MB" ]]; then
    SWAPSIZE_MB=$RECOMMENDED_SWAP_MB
else
    if ! [[ "$USER_SWAP_MB" =~ ^[0-9]+$ ]]; then
        echo "[X] 输入无效，必须为数字。退出。"
        exit 1
    fi
    SWAPSIZE_MB=$USER_SWAP_MB
fi

echo "将创建大小为 ${SWAPSIZE_MB} MB 的 swap 文件。"

# 选择创建方式
echo
echo "选择用于创建 swap 文件的方法："
echo "1) fallocate（推荐，更快）"
echo "2) dd（兼容性更强）"
read -p "请输入 1 或 2 选择方法: " choice

create_swapfile_fallocate() {
    echo "[*] 尝试使用 fallocate 创建 swap 文件..."
    if command -v fallocate >/dev/null; then
        sudo fallocate -l ${SWAPSIZE_MB}M $SWAPFILE
        echo "[+] 使用 fallocate 成功创建 swap 文件。"
    else
        echo "[!] 系统不支持 fallocate。"
        return 1
    fi
}

create_swapfile_dd() {
    echo "[*] 尝试使用 dd 创建 swap 文件..."
    if command -v dd >/dev/null; then
        sudo dd if=/dev/zero of=$SWAPFILE bs=1M count=$SWAPSIZE_MB status=progress
        echo "[+] 使用 dd 成功创建 swap 文件。"
    else
        echo "[!] 系统不支持 dd。"
        return 1
    fi
}

# 根据选择执行创建流程
if [ "$choice" = "1" ]; then
    create_swapfile_fallocate || create_swapfile_dd || { echo "[X] 创建 swap 文件失败。"; exit 1; }
elif [ "$choice" = "2" ]; then
    create_swapfile_dd || create_swapfile_fallocate || { echo "[X] 创建 swap 文件失败。"; exit 1; }
else
    echo "[X] 无效输入，退出。"
    exit 1
fi

# 后续配置
sudo chmod 600 $SWAPFILE
sudo mkswap $SWAPFILE
sudo swapon $SWAPFILE
echo "[+] swap 文件已启用。"

# 自动添加到 /etc/fstab
if grep -qF "$SWAPFILE" /etc/fstab; then
    echo "[*] /etc/fstab 中已存在 swapfile 条目，跳过写入。"
else
    echo "$SWAPFILE none swap sw 0 0" | sudo tee -a /etc/fstab
    echo "[+] 已添加到 /etc/fstab，实现开机自动挂载。"
fi

# 提示 swappiness 设置
echo
echo "[!] 当前系统 swappiness 值为：$(cat /proc/sys/vm/swappiness)"
echo "[!] 若希望永久设置为例如 10，请手动执行以下命令："
echo "    echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf"
echo "    sudo sysctl -p"
echo
echo "[✔] swap 文件配置完成。"