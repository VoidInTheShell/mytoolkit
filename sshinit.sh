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

echo ""
echo "========================================"
echo "SSH 端口配置"
echo "========================================"

# 检查当前 SSH 端口
CURRENT_PORT=$(grep -E "^Port " "$CONFIG_FILE" | awk '{print $2}')
if [[ -z "$CURRENT_PORT" ]]; then
	CURRENT_PORT=22
fi

echo "当前 SSH 端口: $CURRENT_PORT"
read -p "是否修改 SSH 端口? (y/n): " CHANGE_PORT

if [[ "$CHANGE_PORT" == "y" || "$CHANGE_PORT" == "Y" ]]; then
	read -p "请输入新的 SSH 端口号 (1024-65535): " NEW_PORT
	if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [ "$NEW_PORT" -lt 1024 ] || [ "$NEW_PORT" -gt 65535 ]; then
		echo "端口号无效，请输入 1024-65535 之间的数字"
		exit 1
	fi
else
	NEW_PORT=$CURRENT_PORT
	echo "保持当前端口: $NEW_PORT"
fi

echo ""
echo "========================================"
echo "创建或选择登录用户"
echo "========================================"

# 列出当前存在的非系统用户（UID >= 1000）
echo "当前系统中的普通用户:"
existing_users=$(awk -F: '$3 >= 1000 && $3 < 65534 {print $1}' /etc/passwd)
if [[ -z "$existing_users" ]]; then
	echo "  (无)"
else
	echo "$existing_users" | while read user; do
		groups_info=$(groups "$user" 2>/dev/null | cut -d: -f2)
		echo "  - $user (所属组: $groups_info)"
	done
fi

echo ""
read -p "请输入要使用的用户名 (新建或使用已有): " NEW_USER

if [[ -z "$NEW_USER" ]] || ! [[ "$NEW_USER" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
	echo "用户名无效，必须以小写字母或下划线开头，只能包含小写字母、数字、下划线和连字符"
	exit 1
fi

# 检查用户是否已存在
USER_EXISTS=false
if id "$NEW_USER" &>/dev/null; then
	USER_EXISTS=true
	echo ""
	echo "⚠️  用户 $NEW_USER 已存在"

	# 检查用户是否在 sudo/wheel 组
	USER_IN_SUDO=false
	if groups "$NEW_USER" 2>/dev/null | grep -qE '\b(sudo|wheel)\b'; then
		USER_IN_SUDO=true
		echo "  ✅ 用户已在 sudo/wheel 组"
	else
		echo "  ❌ 用户不在 sudo/wheel 组"
	fi

	# 检查是否已有 SSH 公钥
	USER_HOME=$(eval echo "~$NEW_USER")
	AUTHORIZED_KEYS="$USER_HOME/.ssh/authorized_keys"
	if [[ -f "$AUTHORIZED_KEYS" ]]; then
		KEY_COUNT=$(grep -c "^ssh-" "$AUTHORIZED_KEYS" 2>/dev/null || echo 0)
		echo "  ✅ 已配置 $KEY_COUNT 个 SSH 公钥"
	else
		echo "  ❌ 未配置 SSH 公钥"
	fi

	echo ""
	read -p "是否使用此用户? (y/n): " USE_EXISTING
	if [[ "$USE_EXISTING" != "y" && "$USE_EXISTING" != "Y" ]]; then
		echo "请重新运行脚本并输入不同的用户名"
		exit 1
	fi
else
	echo "用户 $NEW_USER 不存在，将创建新用户"
fi

# 创建用户（如果不存在）
if [[ "$USER_EXISTS" == false ]]; then
	useradd -m -s /bin/bash "$NEW_USER"
	if [[ $? -ne 0 ]]; then
		echo "创建用户失败"
		exit 1
	fi
	echo "✅ 用户 $NEW_USER 创建成功"

	# 询问是否设置密码
	echo ""
	read -p "是否为用户设置密码? (y/n): " SET_PASSWORD
	if [[ "$SET_PASSWORD" == "y" || "$SET_PASSWORD" == "Y" ]]; then
		passwd "$NEW_USER"
	fi
fi

# 添加到 sudo 组（如果尚未添加）
if [[ "$USER_EXISTS" == false ]] || [[ "$USER_IN_SUDO" == false ]]; then
	echo ""
	echo "正在添加用户到 sudo/wheel 组..."
	usermod -aG sudo "$NEW_USER" 2>/dev/null || usermod -aG wheel "$NEW_USER" 2>/dev/null
	if [[ $? -eq 0 ]]; then
		echo "✅ 用户 $NEW_USER 已添加到 sudo 组"
	else
		echo "⚠️  警告: 无法将用户添加到 sudo 组，请手动添加"
	fi
fi

# 配置 SSH 公钥
echo ""
echo "========================================"
echo "配置 SSH 公钥"
echo "========================================"

USER_HOME=$(eval echo "~$NEW_USER")
SSH_DIR="$USER_HOME/.ssh"
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"

# 检查是否已有公钥
if [[ -f "$AUTHORIZED_KEYS" ]] && [[ -s "$AUTHORIZED_KEYS" ]]; then
	echo "⚠️  检测到 authorized_keys 文件已存在"
	echo "当前公钥数量: $(grep -c "^ssh-" "$AUTHORIZED_KEYS" 2>/dev/null || echo 0)"
	echo ""
	echo "请选择操作:"
	echo "  1) 追加新公钥（保留现有公钥）"
	echo "  2) 替换所有公钥（删除现有公钥）"
	echo "  3) 跳过公钥配置"
	read -p "请输入选项 (1/2/3): " KEY_OPTION

	case $KEY_OPTION in
		1)
			KEY_MODE="append"
			echo "将追加新公钥"
			;;
		2)
			KEY_MODE="replace"
			echo "将替换所有公钥"
			;;
		3)
			KEY_MODE="skip"
			echo "跳过公钥配置"
			;;
		*)
			echo "无效选项，跳过公钥配置"
			KEY_MODE="skip"
			;;
	esac
else
	KEY_MODE="append"
	echo "未检测到现有公钥，将添加新公钥"
fi

# 处理公钥配置
if [[ "$KEY_MODE" != "skip" ]]; then
	echo ""
	echo "请粘贴您的 SSH 公钥 (通常在 ~/.ssh/id_rsa.pub 或 ~/.ssh/id_ed25519.pub):"
	echo "提示: 可以使用 Ctrl+D 结束输入，或输入单独一行 'END' 结束"
	echo ""

	# 读取公钥（支持多行）
	SSH_KEY=""
	while IFS= read -r line; do
		if [[ "$line" == "END" ]]; then
			break
		fi
		SSH_KEY+="$line"$'\n'
	done

	# 去除末尾的换行符
	SSH_KEY=$(echo "$SSH_KEY" | sed 's/[[:space:]]*$//')

	# 验证公钥格式
	if [[ -z "$SSH_KEY" ]]; then
		echo "⚠️  未输入公钥，跳过公钥配置"
	else
		if ! [[ "$SSH_KEY" =~ ^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)[[:space:]] ]]; then
			echo "⚠️  警告: 公钥格式可能不正确，但仍将继续..."
		fi

		# 检查公钥是否已存在
		if [[ -f "$AUTHORIZED_KEYS" ]] && grep -qF "$SSH_KEY" "$AUTHORIZED_KEYS" 2>/dev/null; then
			echo "⚠️  此公钥已存在于 authorized_keys 中，跳过添加"
		else
			# 创建 .ssh 目录
			mkdir -p "$SSH_DIR"
			if [[ $? -ne 0 ]]; then
				echo "❌ 创建 .ssh 目录失败"
				exit 1
			fi

			# 立即设置目录所有者和权限
			chown "$NEW_USER:$NEW_USER" "$SSH_DIR"
			if [[ $? -ne 0 ]]; then
				echo "❌ 设置 .ssh 目录所有者失败"
				exit 1
			fi

			chmod 700 "$SSH_DIR"
			if [[ $? -ne 0 ]]; then
				echo "❌ 设置 .ssh 目录权限失败"
				exit 1
			fi

			# 写入公钥
			if [[ "$KEY_MODE" == "replace" ]]; then
				echo "$SSH_KEY" > "$AUTHORIZED_KEYS"
			else
				echo "$SSH_KEY" >> "$AUTHORIZED_KEYS"
			fi

			if [[ $? -ne 0 ]]; then
				echo "❌ 写入公钥失败"
				exit 1
			fi

			# 立即设置公钥文件所有者和权限
			chown "$NEW_USER:$NEW_USER" "$AUTHORIZED_KEYS"
			if [[ $? -ne 0 ]]; then
				echo "❌ 设置 authorized_keys 文件所有者失败"
				exit 1
			fi

			chmod 600 "$AUTHORIZED_KEYS"
			if [[ $? -ne 0 ]]; then
				echo "❌ 设置 authorized_keys 文件权限失败"
				exit 1
			fi

			# 验证最终权限设置
			echo ""
			echo "正在验证权限设置..."
			ACTUAL_DIR_OWNER=$(stat -c '%U:%G' "$SSH_DIR" 2>/dev/null || stat -f '%Su:%Sg' "$SSH_DIR" 2>/dev/null)
			ACTUAL_DIR_PERM=$(stat -c '%a' "$SSH_DIR" 2>/dev/null || stat -f '%Lp' "$SSH_DIR" 2>/dev/null)
			ACTUAL_FILE_OWNER=$(stat -c '%U:%G' "$AUTHORIZED_KEYS" 2>/dev/null || stat -f '%Su:%Sg' "$AUTHORIZED_KEYS" 2>/dev/null)
			ACTUAL_FILE_PERM=$(stat -c '%a' "$AUTHORIZED_KEYS" 2>/dev/null || stat -f '%Lp' "$AUTHORIZED_KEYS" 2>/dev/null)

			echo "  📁 $SSH_DIR"
			echo "     所有者: $ACTUAL_DIR_OWNER (期望: $NEW_USER:$NEW_USER)"
			echo "     权限: $ACTUAL_DIR_PERM (期望: 700)"
			echo "  📄 $AUTHORIZED_KEYS"
			echo "     所有者: $ACTUAL_FILE_OWNER (期望: $NEW_USER:$NEW_USER)"
			echo "     权限: $ACTUAL_FILE_PERM (期望: 600)"

			# 检查权限是否正确
			if [[ "$ACTUAL_DIR_OWNER" != "$NEW_USER:$NEW_USER" ]] || [[ "$ACTUAL_DIR_PERM" != "700" ]]; then
				echo ""
				echo "❌ 警告: .ssh 目录权限设置不正确！"
				echo "   这可能导致 SSH 登录失败，请手动检查"
			elif [[ "$ACTUAL_FILE_OWNER" != "$NEW_USER:$NEW_USER" ]] || [[ "$ACTUAL_FILE_PERM" != "600" ]]; then
				echo ""
				echo "❌ 警告: authorized_keys 文件权限设置不正确！"
				echo "   这可能导致 SSH 登录失败，请手动检查"
			else
				echo ""
				echo "✅ SSH 公钥已成功配置，权限验证通过"
				echo "   公钥文件位置: $AUTHORIZED_KEYS"
			fi
		fi
	fi
fi

# 修改 SSH 配置
echo ""
echo "========================================"
echo "更新 SSH 安全配置"
echo "========================================"

CONFIG_CHANGED=false

# 检查并设置端口
if [[ "$NEW_PORT" != "$CURRENT_PORT" ]]; then
	echo "正在修改 SSH 端口: $CURRENT_PORT -> $NEW_PORT"
	sed -i "s/^#Port 22/Port $NEW_PORT/" "$CONFIG_FILE"
	sed -i "s/^Port [0-9]*/Port $NEW_PORT/" "$CONFIG_FILE"
	# 如果没有 Port 行，则添加
	if ! grep -q "^Port " "$CONFIG_FILE"; then
		echo "Port $NEW_PORT" >> "$CONFIG_FILE"
	fi
	CONFIG_CHANGED=true
fi

# 检查并禁用 Root 登录
CURRENT_ROOT=$(grep -E "^PermitRootLogin " "$CONFIG_FILE" | awk '{print $2}')
if [[ "$CURRENT_ROOT" != "no" ]]; then
	echo "正在禁用 Root 登录"
	sed -i "s/^#PermitRootLogin yes/PermitRootLogin no/" "$CONFIG_FILE"
	sed -i "s/^#PermitRootLogin .*/PermitRootLogin no/" "$CONFIG_FILE"
	sed -i "s/^PermitRootLogin .*/PermitRootLogin no/" "$CONFIG_FILE"
	# 如果没有 PermitRootLogin 行，则添加
	if ! grep -q "^PermitRootLogin " "$CONFIG_FILE"; then
		echo "PermitRootLogin no" >> "$CONFIG_FILE"
	fi
	CONFIG_CHANGED=true
else
	echo "✅ Root 登录已禁用，跳过"
fi

# 检查并禁用密码认证
CURRENT_PASSWORD=$(grep -E "^PasswordAuthentication " "$CONFIG_FILE" | awk '{print $2}')
if [[ "$CURRENT_PASSWORD" != "no" ]]; then
	echo "正在禁用密码认证"
	sed -i "s/^#PasswordAuthentication yes/PasswordAuthentication no/" "$CONFIG_FILE"
	sed -i "s/^#PasswordAuthentication .*/PasswordAuthentication no/" "$CONFIG_FILE"
	sed -i "s/^PasswordAuthentication .*/PasswordAuthentication no/" "$CONFIG_FILE"
	# 如果没有 PasswordAuthentication 行，则添加
	if ! grep -q "^PasswordAuthentication " "$CONFIG_FILE"; then
		echo "PasswordAuthentication no" >> "$CONFIG_FILE"
	fi
	CONFIG_CHANGED=true
else
	echo "✅ 密码认证已禁用，跳过"
fi

# 重启 SSH 服务（仅在配置有变更时）
if [[ "$CONFIG_CHANGED" == true ]]; then
	echo ""
	echo "========================================"
	echo "重启 SSH 服务"
	echo "========================================"
	systemctl restart ssh || systemctl restart sshd
	if [[ $? -ne 0 ]]; then
		echo "❌ SSH 服务重启失败，请检查配置文件"
		echo "   可以使用备份恢复: cp $BACKUP_FILE $CONFIG_FILE"
		exit 1
	fi
	echo "✅ SSH 服务已重启"
else
	echo ""
	echo "✅ SSH 配置无需更改"
fi

# 显示配置摘要
echo ""
echo "========================================"
echo "✅ SSH 安全配置已完成！"
echo "========================================"
echo "SSH 端口: $NEW_PORT"
echo "登录用户名: $NEW_USER"
echo "Root 登录: 已禁用"
echo "密码认证: 已禁用"
echo "公钥认证: 已启用"
echo ""
echo "⚠️  重要提示："
echo "1. 请不要关闭当前 SSH 连接"
echo "2. 打开新终端测试登录:"
echo "   ssh -p $NEW_PORT $NEW_USER@YOUR_SERVER_IP"
echo "3. 确认可以正常登录后，再关闭当前连接"
echo "4. 如果配置有误，可以使用备份文件恢复:"
echo "   cp $BACKUP_FILE $CONFIG_FILE && systemctl restart ssh"
echo "========================================"
