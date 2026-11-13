-- Dedicated acceptance/demo table. Never alters the pre-existing users table.
CREATE TABLE IF NOT EXISTS s_rest_users_v1 (
  id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(200) NOT NULL,
  email VARCHAR(254) NOT NULL UNIQUE,
  age INT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
