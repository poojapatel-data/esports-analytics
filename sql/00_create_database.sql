-- 00_create_database.sql

-- 1) Create a dedicated database (UTF-8 all the way)
CREATE DATABASE IF NOT EXISTS esports_analytics_new
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;
  
-- 4) Use this DB going forward
USE esports_analytics_new;

-- 5) (Optional) Allow local CSV loads for this server session
--    If PERSIST isn’t allowed on your host, you can set it per-session in the client:
--    mysql --local-infile=1 ...
SET PERSIST local_infile = 1;

