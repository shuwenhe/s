-- MySQL Test Account Setup Script
-- 用于 S 语言 MySQL CRUD 测试

-- 检查现有配置
SELECT '=== 检查现有数据库 ===' as '';
SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 's_test';

SELECT '=== 检查现有用户 ===' as '';
SELECT User, Host, plugin FROM mysql.user WHERE User = 's_test' AND Host = '127.0.0.1';

-- 创建数据库
CREATE DATABASE IF NOT EXISTS s_test CHARACTER SET utf8mb4;

-- 创建用户（强烈建议修改密码为强密码）
CREATE USER IF NOT EXISTS 's_test'@'127.0.0.1' IDENTIFIED BY 's_test_password';

-- 授予最小权限
GRANT CREATE TEMPORARY TABLES ON s_test.* TO 's_test'@'127.0.0.1';

-- 刷新权限
FLUSH PRIVILEGES;

-- 验证配置
SELECT '=== 配置验证成功 ===' as '';
SELECT '数据库:' as '', SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME = 's_test';
SELECT '用户:' as '', User, Host FROM mysql.user WHERE User = 's_test';
SELECT '权限:' as '';
SHOW GRANTS FOR 's_test'@'127.0.0.1';
