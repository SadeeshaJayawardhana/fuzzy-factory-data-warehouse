 
-- 01b_load_staging_from_files.sql
-- Purpose: Load all 6 staging tables straight from the source files

USE ToyStore_StagingDB;
GO

SET NOCOUNT ON;
GO

-- clear existing rows, children before parents
DELETE FROM stg_order_item_refunds;
DELETE FROM stg_order_items;
DELETE FROM stg_orders;
DELETE FROM stg_website_pageviews;
DELETE FROM stg_website_sessions;
DELETE FROM stg_products;
GO

 -- stg_products: only 4 rows, entered directly

INSERT INTO stg_products (product_id, created_at, product_name) VALUES
(1, '2012-03-19 08:00:00', 'The Original Mr. Fuzzy'),
(2, '2013-01-06 13:00:00', 'The Forever Love Bear'),
(3, '2013-12-12 09:00:00', 'The Birthday Sugar Panda'),
(4, '2014-02-05 10:00:00', 'The Hudson River Mini Bear');
GO

 -- stg_orders, stg_order_items, stg_order_item_refunds: CSV files
 
DECLARE @sql NVARCHAR(MAX);
DECLARE @path VARCHAR(300) = 'C:\Users\sadee\Documents\DWBI\DWBI Project\fuzzy-factory-data-warehouse\sources\';
SET @sql = '
BULK INSERT stg_orders
FROM ''' + @path + 'orders.csv''
WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', ROWTERMINATOR = ''0x0a'', TABLOCK);';
EXEC(@sql);

SET @sql = '
BULK INSERT stg_order_items
FROM ''' + @path + 'order_items.csv''
WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', ROWTERMINATOR = ''0x0a'', TABLOCK);';
EXEC(@sql);

SET @sql = '
BULK INSERT stg_order_item_refunds
FROM ''' + @path + 'order_item_refunds.csv''
WITH (FORMAT = ''CSV'', FIRSTROW = 2, CODEPAGE = ''65001'', ROWTERMINATOR = ''0x0a'', TABLOCK);';
EXEC(@sql);
GO

 
-- stg_website_sessions: JSON file, read with OPENROWSET + OPENJSON
 
DECLARE @path VARCHAR(300) = 'C:\Users\sadee\Documents\DWBI\DWBI Project\fuzzy-factory-data-warehouse\sources\';
DECLARE @json_sql NVARCHAR(MAX);

SET @json_sql = N'
INSERT INTO stg_website_sessions
    (website_session_id, created_at, user_id, is_repeat_session,
     utm_source, utm_campaign, utm_content, device_type, http_referer)
SELECT
    sess.website_session_id,
    CONVERT(DATETIME2, sess.created_at, 126),
    sess.user_id,
    sess.is_repeat_session,
    sess.utm_source,
    sess.utm_campaign,
    sess.utm_content,
    sess.device_type,
    sess.http_referer
FROM OPENROWSET(BULK ''' + @path + N'website_sessions.json'', SINGLE_CLOB) AS raw_file
CROSS APPLY OPENJSON(raw_file.BulkColumn)
WITH (
    website_session_id INT,
    created_at          VARCHAR(30),
    user_id             INT,
    is_repeat_session   BIT,
    utm_source          VARCHAR(50),
    utm_campaign        VARCHAR(50),
    utm_content         VARCHAR(50),
    device_type         VARCHAR(20),
    http_referer        VARCHAR(200)
) AS sess;';

EXEC sp_executesql @json_sql;
GO

 
-- stg_website_pageviews: JSON file, same method
 
DECLARE @path VARCHAR(300) = 'C:\Users\sadee\Documents\DWBI\DWBI Project\fuzzy-factory-data-warehouse\sources\';
DECLARE @json_sql2 NVARCHAR(MAX);

SET @json_sql2 = N'
INSERT INTO stg_website_pageviews
    (website_pageview_id, created_at, website_session_id, pageview_url)
SELECT
    pv.website_pageview_id,
    CONVERT(DATETIME2, pv.created_at, 126),
    pv.website_session_id,
    pv.pageview_url
FROM OPENROWSET(BULK ''' + @path + N'website_pageviews.json'', SINGLE_CLOB) AS raw_file
CROSS APPLY OPENJSON(raw_file.BulkColumn)
WITH (
    website_pageview_id INT,
    created_at           VARCHAR(30),
    website_session_id   INT,
    pageview_url         VARCHAR(200)
) AS pv;';

EXEC sp_executesql @json_sql2;
GO

 
-- Check the row counts. Expected with the full dataset:

SELECT 'stg_products' AS tbl, COUNT(*) AS n FROM stg_products
UNION ALL SELECT 'stg_website_sessions', COUNT(*) FROM stg_website_sessions
UNION ALL SELECT 'stg_website_pageviews', COUNT(*) FROM stg_website_pageviews
UNION ALL SELECT 'stg_orders', COUNT(*) FROM stg_orders
UNION ALL SELECT 'stg_order_items', COUNT(*) FROM stg_order_items
UNION ALL SELECT 'stg_order_item_refunds', COUNT(*) FROM stg_order_item_refunds;
GO
