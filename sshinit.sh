#!/bin/bash

# 确保以 root 身份运行
if [[ $EUID -ne 0 ]]; then
	   echo "此脚本需要以 root 身份运行" 
	      exit 1
fi

CONFIG_FILE="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.bak_$(date +%F_%T)"

# 备份 SSH 配置文件
cp "$CONFIG_FILE" "$BACKUP_FILE"
if [[ $? -ne 0 ]]; then
	    echo "备份 SSH 配置文件失败，脚本终止"
	        exit 1
	else
		    echo "SSH 配置文件已备份至: $BACKUP_FILE"
fi

# 让用户输入新的 SSH 端口
read -p "请输入新的 SSH 端口号: " NEW_PORT
if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
	    echo "端口号无效，请输入 1024-65535 之间的数字"
	        exit 1
fi

# 修改 SSH 配置文件
sed -i "s/^#Port 22/Port $NEW_PORT/" "$CONFIG_FILE"
sed -i "s/^Port [0-9]*/Port $NEW_PORT/" "$CONFIG_FILE"
sed -i "s/^#PermitRootLogin yes/PermitRootLogin no/" "$CONFIG_FILE"
sed -i "s/^PermitRootLogin .*/PermitRootLogin no/" "$CONFIG_FILE"
sed -i "s/^#PasswordAuthentication yes/PasswordAuthentication no/" "$CONFIG_FILE"
sed -i "s/^PasswordAuthentication .*/PasswordAuthentication no/" "$CONFIG_FILE"

# 重启 SSH 服务
systemctl restart ssh
if [[ $? -ne 0 ]]; then
	    echo "SSH 服务重启失败，请检查配置文件"
	        exit 1
	else
		    echo "SSH 配置已更新，当前 SSH 端口: $NEW_PORT"
fi

