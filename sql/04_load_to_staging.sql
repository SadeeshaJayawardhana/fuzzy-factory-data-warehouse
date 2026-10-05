
USE ToyStore_StagingDB;
GO

SET NOCOUNT ON;
GO



  -- STEP 1 - CLEAR EXISTING STAGING DATA



TRUNCATE TABLE stg_order_item_refunds;
TRUNCATE TABLE stg_order_items;
TRUNCATE TABLE stg_orders;
TRUNCATE TABLE stg_website_pageviews;
TRUNCATE TABLE stg_website_sessions;
TRUNCATE TABLE stg_products;
GO



 --  STEP 2 - LOAD PRODUCTS FROM CSV



BULK INSERT stg_products
FROM 'C:\Users\USER\Desktop\dwbi E-commerce Project - Copy\fuzzy-factory-data-warehouse\source1\products.csv'
WITH
(
    FORMAT = 'CSV',
    FIRSTROW = 2,
    CODEPAGE = '65001',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);
GO



   --STEP 3 - LOAD WEBSITE SESSIONS FROM JSON


DECLARE @path VARCHAR(500) =
'C:\Users\USER\Desktop\dwbi E-commerce Project - Copy\fuzzy-factory-data-warehouse\source1\';

DECLARE @json_sql NVARCHAR(MAX);

SET @json_sql = N'
INSERT INTO stg_website_sessions
(
    website_session_id,
    created_at,
    user_id,
    is_repeat_session,
    utm_source,
    utm_campaign,
    utm_content,
    device_type,
    http_referer
)
SELECT
    sess.website_session_id,
    CONVERT(DATETIME, sess.created_at, 120),
    sess.user_id,
    sess.is_repeat_session,
    sess.utm_source,
    sess.utm_campaign,
    sess.utm_content,
    sess.device_type,
    sess.http_referer
FROM OPENROWSET
(
    BULK ''' + @path + N'website_sessions.json'',
    SINGLE_CLOB
) AS raw_file

CROSS APPLY OPENJSON(raw_file.BulkColumn)

WITH
(
    website_session_id INT,
    created_at          VARCHAR(30),
    user_id             INT,
    is_repeat_session   BIT,
    utm_source          VARCHAR(50),
    utm_campaign        VARCHAR(50),
    utm_content         VARCHAR(50),
    device_type         VARCHAR(20),
    http_referer        VARCHAR(200)
) AS sess;
';

EXEC sp_executesql @json_sql;
GO



  -- STEP 4 - LOAD WEBSITE PAGEVIEWS FROM JSON
 

DECLARE @path VARCHAR(500) =
'C:\Users\USER\Desktop\dwbi E-commerce Project - Copy\fuzzy-factory-data-warehouse\source1\';

DECLARE @json_sql2 NVARCHAR(MAX);

SET @json_sql2 = N'
INSERT INTO stg_website_pageviews
(
    website_pageview_id,
    created_at,
    website_session_id,
    pageview_url
)
SELECT
    pv.website_pageview_id,
    CONVERT(DATETIME, pv.created_at, 120),
    pv.website_session_id,
    pv.pageview_url
FROM OPENROWSET
(
    BULK ''' + @path + N'website_pageviews.json'',
    SINGLE_CLOB
) AS raw_file

CROSS APPLY OPENJSON(raw_file.BulkColumn)

WITH
(
    website_pageview_id INT,
    created_at           VARCHAR(30),
    website_session_id   INT,
    pageview_url         VARCHAR(200)
) AS pv;
';

EXEC sp_executesql @json_sql2;
GO



   --STEP 5 - LOAD ORDERS FROM CSV
   

BULK INSERT stg_orders
FROM 'C:\Users\USER\Desktop\dwbi E-commerce Project - Copy\fuzzy-factory-data-warehouse\source1\orders.csv'
WITH
(
    FORMAT = 'CSV',
    FIRSTROW = 2,
    CODEPAGE = '65001',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);
GO



   --STEP 6 - LOAD ORDER ITEMS FROM CSV
  

BULK INSERT stg_order_items
FROM 'C:\Users\USER\Desktop\dwbi E-commerce Project - Copy\fuzzy-factory-data-warehouse\source1\order_items.csv'
WITH
(
    FORMAT = 'CSV',
    FIRSTROW = 2,
    CODEPAGE = '65001',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);
GO



   --STEP 7 - LOAD ORDER ITEM REFUNDS FROM CSV
 

BULK INSERT stg_order_item_refunds
FROM 'C:\Users\USER\Desktop\dwbi E-commerce Project - Copy\fuzzy-factory-data-warehouse\source1\order_item_refunds.csv'
WITH
(
    FORMAT = 'CSV',
    FIRSTROW = 2,
    CODEPAGE = '65001',
    ROWTERMINATOR = '0x0a',
    TABLOCK
);
GO



   --STEP 8 - VALIDATE ROW COUNTS
 

SELECT
    'stg_products' AS table_name,
    COUNT(*) AS row_count
FROM stg_products

UNION ALL

SELECT
    'stg_website_sessions',
    COUNT(*)
FROM stg_website_sessions

UNION ALL

SELECT
    'stg_website_pageviews',
    COUNT(*)
FROM stg_website_pageviews

UNION ALL

SELECT
    'stg_orders',
    COUNT(*)
FROM stg_orders

UNION ALL

SELECT
    'stg_order_items',
    COUNT(*)
FROM stg_order_items

UNION ALL

SELECT
    'stg_order_item_refunds',
    COUNT(*)
FROM stg_order_item_refunds;
GO