#!/bin/bash
#
# Interactive MySQL Test Account Setup
# 交互式 MySQL 测试账户设置脚本

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear
echo -e "${BLUE}"
echo "╔════════════════════════════════════════════════════════════╗"
echo "║     MySQL Test Account Setup for S Language CRUD Test      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# 获取配置参数
echo -e "${YELLOW}请输入 MySQL 配置信息${NC}"
echo ""

read -p "MySQL 主机地址 [127.0.0.1]: " MYSQL_HOST
MYSQL_HOST="${MYSQL_HOST:-127.0.0.1}"

read -p "MySQL 端口 [3306]: " MYSQL_PORT
MYSQL_PORT="${MYSQL_PORT:-3306}"

read -p "MySQL 管理员用户 [root]: " MYSQL_ROOT_USER
MYSQL_ROOT_USER="${MYSQL_ROOT_USER:-root}"

# 安全地读取密码
read -sp "MySQL 管理员密码: " MYSQL_ROOT_PASSWORD
echo ""

# 验证测试账户密码
read -sp "测试账户密码 [s_test_password]: " TEST_PASSWORD
echo ""
TEST_PASSWORD="${TEST_PASSWORD:-s_test_password}"

# 确认
echo ""
echo -e "${YELLOW}确认配置信息：${NC}"
echo "  主机: $MYSQL_HOST"
echo "  端口: $MYSQL_PORT"
echo "  管理员: $MYSQL_ROOT_USER"
echo "  测试用户: s_test"
echo "  测试数据库: s_test"
echo ""
read -p "是否继续？ (y/n) [y]: " CONFIRM
CONFIRM="${CONFIRM:-y}"

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
  echo "已取消"
  exit 0
fi

echo ""
echo -e "${YELLOW}[*] 测试连接...${NC}"

if ! mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1;" > /dev/null 2>&1; then
  echo -e "${RED}[✗] 无法连接到 MySQL，请检查配置${NC}"
  exit 1
fi

echo -e "${GREEN}[✓] 连接成功${NC}"
echo ""

# 执行设置
echo -e "${YELLOW}[*] 创建数据库和账户...${NC}"
echo ""

mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_ROOT_USER" -p"$MYSQL_ROOT_PASSWORD" << EOSQL
CREATE DATABASE IF NOT EXISTS s_test CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS 's_test'@'127.0.0.1' IDENTIFIED BY '$TEST_PASSWORD';
GRANT CREATE TEMPORARY TABLES ON s_test.* TO 's_test'@'127.0.0.1';
FLUSH PRIVILEGES;

-- 验证
SELECT '=== 数据库 ===' as '';
SHOW DATABASES LIKE 's_test';
SELECT '=== 用户 ===' as '';
SELECT User, Host, plugin FROM mysql.user WHERE User = 's_test';
SELECT '=== 权限 ===' as '';
SHOW GRANTS FOR 's_test'@'127.0.0.1';
EOSQL

if [ $? -ne 0 ]; then
  echo -e "${RED}[✗] 设置失败${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}✓ 设置成功！${NC}"
echo ""
echo -e "${YELLOW}下一步 - 运行 CRUD 测试：${NC}"
echo ""
echo "  export MYSQL_HOST=$MYSQL_HOST"
echo "  export MYSQL_PORT=$MYSQL_PORT"
echo "  export MYSQL_USER=s_test"
echo "  export MYSQL_PASSWORD='$TEST_PASSWORD'"
echo "  export MYSQL_DATABASE=s_test"
echo ""
echo "  make compiler"
echo "  sh test/mysql/run.sh"
echo ""
