#!/bin/bash
#
# MySQL Test Account Setup Script
# 为 S 语言 MySQL CRUD 测试创建专用数据库和账户
#
# 使用方法：
#   MYSQL_ROOT_PASSWORD='your_root_password' bash setup_test_account.sh
#   MYSQL_ROOT_PASSWORD='your_root_password' TEST_PASSWORD='custom_test_pwd' bash setup_test_account.sh

set -e

# 配置参数
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
TEST_USER="s_test"
TEST_PASSWORD="${TEST_PASSWORD:-s_test_password_123}"
TEST_DB="s_test"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}========================================${NC}"
echo -e "${YELLOW}MySQL Test Account Setup for S Language${NC}"
echo -e "${YELLOW}========================================${NC}"
echo ""

# 验证参数
if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
  echo -e "${RED}[错误] MYSQL_ROOT_PASSWORD 环境变量未设置${NC}"
  echo ""
  echo "使用方法："
  echo "  MYSQL_ROOT_PASSWORD='your_password' bash $0"
  echo ""
  echo "例如："
  echo "  MYSQL_ROOT_PASSWORD='root_password' bash $0"
  echo "  MYSQL_ROOT_PASSWORD='root_password' TEST_PASSWORD='custom_pwd' bash $0"
  echo ""
  exit 1
fi

echo -e "${YELLOW}[*] 配置信息：${NC}"
echo "  MySQL 主机: $MYSQL_HOST"
echo "  MySQL 端口: $MYSQL_PORT"
echo "  管理员用户: $MYSQL_ROOT_USER"
echo "  测试用户: $TEST_USER"
echo "  测试数据库: $TEST_DB"
echo ""

# 测试 MySQL 连接
echo -e "${YELLOW}[*] 测试 MySQL 连接...${NC}"
if ! mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; then
  echo -e "${RED}[✗] 无法连接到 MySQL${NC}"
  echo "   请确保："
  echo "   1. MySQL 正在运行: ps aux | grep mysqld"
  echo "   2. 主机地址正确: $MYSQL_HOST"
  echo "   3. 端口正确: $MYSQL_PORT"
  echo "   4. 用户名正确: $MYSQL_ROOT_USER"
  echo "   5. 密码正确"
  exit 2
fi
echo -e "${GREEN}[✓] MySQL 连接成功${NC}"
echo ""

# 检查现有配置
echo -e "${YELLOW}[*] 检查现有配置...${NC}"
echo ""

echo "  检查数据库 '$TEST_DB' 是否存在..."
DB_EXISTS=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -se "SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = '$TEST_DB';" 2>/dev/null || echo "")
if [ -n "$DB_EXISTS" ]; then
  echo -e "    ${YELLOW}✓ 数据库已存在${NC}"
else
  echo "    ✗ 数据库不存在（将创建）"
fi

echo "  检查用户 '$TEST_USER'@'$MYSQL_HOST' 是否存在..."
USER_EXISTS=$(mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -se "SELECT User FROM mysql.user WHERE User = '$TEST_USER' AND Host = '$MYSQL_HOST';" 2>/dev/null || echo "")
if [ -n "$USER_EXISTS" ]; then
  echo -e "    ${YELLOW}⚠ 用户已存在${NC}"
  echo -e "    ${YELLOW}检查现有权限...${NC}"
  mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SHOW GRANTS FOR '$TEST_USER'@'$MYSQL_HOST';" 2>/dev/null || true
else
  echo "    ✗ 用户不存在（将创建）"
fi
echo ""

# 创建数据库和账户
echo -e "${YELLOW}[*] 创建数据库和测试账户...${NC}"
echo ""

mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOSQL
-- 创建数据库
CREATE DATABASE IF NOT EXISTS $TEST_DB CHARACTER SET utf8mb4;

-- 创建用户
CREATE USER IF NOT EXISTS '$TEST_USER'@'$MYSQL_HOST' IDENTIFIED BY '$TEST_PASSWORD';

-- 授予最小权限（仅创建临时表）
GRANT CREATE TEMPORARY TABLES ON $TEST_DB.* TO '$TEST_USER'@'$MYSQL_HOST';

-- 刷新权限
FLUSH PRIVILEGES;

-- 验证
SELECT '--- 数据库检查 ---' as '';
SHOW DATABASES LIKE '$TEST_DB';

SELECT '--- 用户检查 ---' as '';
SELECT User, Host, plugin FROM mysql.user WHERE User = '$TEST_USER';

SELECT '--- 权限检查 ---' as '';
SHOW GRANTS FOR '$TEST_USER'@'$MYSQL_HOST';
EOSQL

if [ $? -eq 0 ]; then
  echo -e "${GREEN}[✓] 数据库和用户创建成功${NC}"
else
  echo -e "${RED}[✗] 创建过程中出错${NC}"
  exit 3
fi
echo ""

# 验证连接
echo -e "${YELLOW}[*] 验证测试账户连接...${NC}"
if mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$TEST_USER" -p"$TEST_PASSWORD" -D "$TEST_DB" -e "SELECT DATABASE();" > /dev/null 2>&1; then
  echo -e "${GREEN}[✓] 测试账户可以正常连接${NC}"
else
  echo -e "${RED}[✗] 测试账户连接失败${NC}"
  exit 4
fi
echo ""

# 完成总结
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}[✓] 设置完成！${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${YELLOW}连接信息：${NC}"
echo "  主机:     $MYSQL_HOST"
echo "  端口:     $MYSQL_PORT"
echo "  用户:     $TEST_USER"
echo "  密码:     $TEST_PASSWORD"
echo "  数据库:   $TEST_DB"
echo ""
echo -e "${YELLOW}运行 CRUD 测试：${NC}"
echo ""
echo "  # 设置环境变量"
echo "  export MYSQL_HOST=$MYSQL_HOST"
echo "  export MYSQL_PORT=$MYSQL_PORT"
echo "  export MYSQL_USER=$TEST_USER"
echo "  export MYSQL_PASSWORD='$TEST_PASSWORD'"
echo "  export MYSQL_DATABASE=$TEST_DB"
echo ""
echo "  # 编译编译器"
echo "  make compiler"
echo ""
echo "  # 运行测试"
echo "  sh test/mysql/run.sh"
echo ""
echo -e "${YELLOW}清理（可选）：${NC}"
echo "  mysql -h $MYSQL_HOST -u $MYSQL_ROOT_USER -p -e \"DROP USER '$TEST_USER'@'$MYSQL_HOST'; DROP DATABASE $TEST_DB;\""
echo ""
