
-- 1. SELECT THE STAGING DATABASE


USE ToyStore_StagingDB;
GO



-- 2. CONFIRM SQL SERVER INFORMATION


SELECT
    SERVERPROPERTY('MachineName') AS MachineName,
    SERVERPROPERTY('ServerName') AS ServerName,
    SERVERPROPERTY('InstanceName') AS InstanceName;
GO



-- 3. CHECK THAT ALL STAGING TABLES CURRENTLY EXIST


SELECT
    TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;
GO



-- 4. CHECK CURRENT NUMBER OF ROWS


SELECT 'stg_products' AS TableName, COUNT(*) AS [RowCount]
FROM stg_products

UNION ALL

SELECT 'stg_website_sessions', COUNT(*)
FROM stg_website_sessions

UNION ALL

SELECT 'stg_website_pageviews', COUNT(*)
FROM stg_website_pageviews

UNION ALL

SELECT 'stg_orders', COUNT(*)
FROM stg_orders

UNION ALL

SELECT 'stg_order_items', COUNT(*)
FROM stg_order_items

UNION ALL

SELECT 'stg_order_item_refunds', COUNT(*)
FROM stg_order_item_refunds;
GO