 
-- 03_load_warehouse_from_staging.sql
-- Purpose: Transform and load. Builds the dimension and fact tables
--          in ToyStore_WarehouseDB from the staging tables in
--          ToyStore_StagingDB (staging -> warehouse).
--
-- Before running:
--   1. Staging tables should be loaded.
--   2. The warehouse tables should be empty. To empty them, run
--      02_create_warehouse_tables.sql again.
--
-- The whole load runs in one transaction. If anything fails, everything
-- is rolled back and the warehouse stays empty.
 
USE ToyStore_WarehouseDB;
GO

SET NOCOUNT ON;
SET LANGUAGE us_english;   -- so month and weekday names come out in English
GO

IF OBJECT_ID('tempdb..#sess_clean') IS NOT NULL DROP TABLE #sess_clean;
GO

BEGIN TRY

    -- --------------------------------------------------------
    -- 0. Pre-checks
    -- --------------------------------------------------------
    IF EXISTS (SELECT 1 FROM dbo.Fact_Sessions)   OR EXISTS (SELECT 1 FROM dbo.Fact_Order_Items)
    OR EXISTS (SELECT 1 FROM dbo.Dim_Date)        OR EXISTS (SELECT 1 FROM dbo.Dim_Product)
    OR EXISTS (SELECT 1 FROM dbo.Dim_Channel)
        THROW 50001, 'Warehouse tables are not empty. Run 02_create_warehouse_tables.sql first to reset them.', 1;

    IF NOT EXISTS (SELECT 1 FROM ToyStore_StagingDB.dbo.stg_website_sessions)
    OR NOT EXISTS (SELECT 1 FROM ToyStore_StagingDB.dbo.stg_orders)
    OR NOT EXISTS (SELECT 1 FROM ToyStore_StagingDB.dbo.stg_order_items)
    OR NOT EXISTS (SELECT 1 FROM ToyStore_StagingDB.dbo.stg_products)
        THROW 50002, 'Staging tables are empty. Load the staging tables first.', 1;

    BEGIN TRANSACTION;

    
    -- 1. Clean the session data once 

    SELECT s.website_session_id,
           YEAR(s.created_at) * 10000 + MONTH(s.created_at) * 100 + DAY(s.created_at) AS date_key,
           s.is_repeat_session,
           ISNULL(NULLIF(LTRIM(RTRIM(s.utm_source)),   ''), 'direct') AS utm_source,
           ISNULL(NULLIF(LTRIM(RTRIM(s.utm_campaign)), ''), 'direct') AS utm_campaign,
           ISNULL(NULLIF(LTRIM(RTRIM(s.utm_content)),  ''), 'direct') AS utm_content,
           LTRIM(RTRIM(s.device_type)) AS device_type
    INTO #sess_clean
    FROM ToyStore_StagingDB.dbo.stg_website_sessions s;

    CREATE UNIQUE CLUSTERED INDEX ix_sess_clean ON #sess_clean (website_session_id);

     
    -- 2. Dim_Date: one row per day from the first to the last date in staging
     
    DECLARE @d0 DATE, @d1 DATE;

    SELECT @d0 = MIN(d), @d1 = MAX(d)
    FROM (
        SELECT CAST(created_at AS DATE) AS d FROM ToyStore_StagingDB.dbo.stg_website_sessions
        UNION ALL
        SELECT CAST(created_at AS DATE)      FROM ToyStore_StagingDB.dbo.stg_orders
        UNION ALL
        SELECT CAST(created_at AS DATE)      FROM ToyStore_StagingDB.dbo.stg_order_items
    ) x;

    WITH cal AS (
        SELECT @d0 AS d
        UNION ALL
        SELECT DATEADD(DAY, 1, d) FROM cal WHERE d < @d1
    )
    INSERT INTO dbo.Dim_Date
        (date_key, full_date, day_num, month_num, month_name, quarter_num, year_num, day_of_week, is_weekend)
    SELECT YEAR(d) * 10000 + MONTH(d) * 100 + DAY(d),
           d,
           DAY(d),
           MONTH(d),
           DATENAME(MONTH, d),
           DATEPART(QUARTER, d),
           YEAR(d),
           DATENAME(WEEKDAY, d),
           CASE WHEN DATENAME(WEEKDAY, d) IN ('Saturday', 'Sunday') THEN 1 ELSE 0 END
    FROM cal
    OPTION (MAXRECURSION 0);

    
    -- 3. Dim_Product: from stg_products (surrogate key is an identity column)
     
    INSERT INTO dbo.Dim_Product (product_id, product_name, launch_date)
    SELECT product_id, product_name, CAST(created_at AS DATE)
    FROM ToyStore_StagingDB.dbo.stg_products
    ORDER BY product_id;

     
    -- 4. Dim_Channel: one row per distinct source/campaign/content/device
    
    INSERT INTO dbo.Dim_Channel (utm_source, utm_campaign, utm_content, device_type)
    SELECT DISTINCT utm_source, utm_campaign, utm_content, device_type
    FROM #sess_clean
    ORDER BY utm_source, utm_campaign, utm_content, device_type;


    -- 5. Fact_Sessions: one row per session.
    --    pageview_count is aggregated from the page views.
     
    INSERT INTO dbo.Fact_Sessions
        (website_session_id, date_key, channel_key, pageview_count, is_repeat_session, converted_flag)
    SELECT sc.website_session_id,
           sc.date_key,
           ch.channel_key,
           ISNULL(pv.pageviews, 0),
           sc.is_repeat_session,
           CASE WHEN o.website_session_id IS NULL THEN 0 ELSE 1 END
    FROM #sess_clean sc
    JOIN dbo.Dim_Channel ch
         ON  ch.utm_source   = sc.utm_source
         AND ch.utm_campaign = sc.utm_campaign
         AND ch.utm_content  = sc.utm_content
         AND ch.device_type  = sc.device_type
    LEFT JOIN (SELECT website_session_id, COUNT(*) AS pageviews
               FROM ToyStore_StagingDB.dbo.stg_website_pageviews
               GROUP BY website_session_id) pv
         ON pv.website_session_id = sc.website_session_id
    LEFT JOIN (SELECT DISTINCT website_session_id
               FROM ToyStore_StagingDB.dbo.stg_orders) o
         ON o.website_session_id = sc.website_session_id
    ORDER BY sc.website_session_id;

     
    -- 6. Fact_Order_Items: one row per order item.
    --    The session (and so the channel) comes from the order.
    --    Refunds are summed per item, 0 when there is none.
    
    INSERT INTO dbo.Fact_Order_Items
        (date_key, product_key, channel_key, order_id, website_session_id,
         is_primary_item, price_usd, cogs_usd, refund_amount_usd)
    SELECT YEAR(oi.created_at) * 10000 + MONTH(oi.created_at) * 100 + DAY(oi.created_at),
           p.product_key,
           ch.channel_key,
           oi.order_id,
           o.website_session_id,
           oi.is_primary_item,
           oi.price_usd,
           oi.cogs_usd,
           ISNULL(r.refund_usd, 0)
    FROM ToyStore_StagingDB.dbo.stg_order_items oi
    JOIN ToyStore_StagingDB.dbo.stg_orders o
         ON o.order_id = oi.order_id
    JOIN #sess_clean sc
         ON sc.website_session_id = o.website_session_id
    JOIN dbo.Dim_Channel ch
         ON  ch.utm_source   = sc.utm_source
         AND ch.utm_campaign = sc.utm_campaign
         AND ch.utm_content  = sc.utm_content
         AND ch.device_type  = sc.device_type
    JOIN dbo.Dim_Product p
         ON p.product_id = oi.product_id
    LEFT JOIN (SELECT order_item_id, SUM(refund_amount_usd) AS refund_usd
               FROM ToyStore_StagingDB.dbo.stg_order_item_refunds
               GROUP BY order_item_id) r
         ON r.order_item_id = oi.order_item_id
    ORDER BY oi.order_item_id;

    
    -- 7. Validation inside the transaction: no rows may be lost.
    --    If a join dropped rows, roll everything back.
    
    IF (SELECT COUNT(*) FROM dbo.Fact_Order_Items) <> (SELECT COUNT(*) FROM ToyStore_StagingDB.dbo.stg_order_items)
        THROW 50003, 'Fact_Order_Items row count does not match stg_order_items. Load rolled back.', 1;

    IF (SELECT COUNT(*) FROM dbo.Fact_Sessions) <> (SELECT COUNT(*) FROM ToyStore_StagingDB.dbo.stg_website_sessions)
        THROW 50004, 'Fact_Sessions row count does not match stg_website_sessions. Load rolled back.', 1;

    COMMIT TRANSACTION;
    PRINT 'Warehouse loaded from staging successfully.';

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Load failed and was rolled back: ' + ERROR_MESSAGE();
    THROW;
END CATCH;
GO

-- Checks (run after the load). 
 
SELECT 'Dim_Date' AS tbl, COUNT(*) AS n FROM dbo.Dim_Date
UNION ALL SELECT 'Dim_Product',      COUNT(*) FROM dbo.Dim_Product
UNION ALL SELECT 'Dim_Channel',      COUNT(*) FROM dbo.Dim_Channel
UNION ALL SELECT 'Fact_Order_Items', COUNT(*) FROM dbo.Fact_Order_Items
UNION ALL SELECT 'Fact_Sessions',    COUNT(*) FROM dbo.Fact_Sessions;

SELECT
  (SELECT SUM(price_usd)         FROM ToyStore_StagingDB.dbo.stg_order_items)        AS staging_revenue,
  (SELECT SUM(price_usd)         FROM dbo.Fact_Order_Items)                          AS warehouse_revenue,
  (SELECT SUM(refund_amount_usd) FROM ToyStore_StagingDB.dbo.stg_order_item_refunds) AS staging_refunds,
  (SELECT SUM(refund_amount_usd) FROM dbo.Fact_Order_Items)                          AS warehouse_refunds,
  (SELECT SUM(pageview_count)    FROM dbo.Fact_Sessions)                             AS warehouse_pageviews,
  (SELECT COUNT(*)               FROM ToyStore_StagingDB.dbo.stg_website_pageviews)  AS staging_pageviews;
GO
