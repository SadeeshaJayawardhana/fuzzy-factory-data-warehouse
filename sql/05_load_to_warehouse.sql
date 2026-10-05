

USE ToyStore_WarehouseDB;
GO

SET NOCOUNT ON;
SET LANGUAGE us_english;
GO



-- Remove temporary table if it already exists


IF OBJECT_ID('tempdb..#sess_clean') IS NOT NULL
    DROP TABLE #sess_clean;
GO


BEGIN TRY

   

    -- Warehouse must be empty before performing this full load.

    IF EXISTS (SELECT 1 FROM dbo.Fact_Sessions)
       OR EXISTS (SELECT 1 FROM dbo.Fact_Order_Items)
       OR EXISTS (SELECT 1 FROM dbo.Dim_Date)
       OR EXISTS (SELECT 1 FROM dbo.Dim_Product)
       OR EXISTS (SELECT 1 FROM dbo.Dim_Channel)

        THROW 50001,
        'Warehouse tables are not empty. Run 02_create_warehouse_tables.sql first to reset them.',
        1;


    -- Check that the required staging tables contain data.

    IF NOT EXISTS
       (SELECT 1 FROM ToyStore_StagingDB.dbo.stg_website_sessions)

       OR NOT EXISTS
       (SELECT 1 FROM ToyStore_StagingDB.dbo.stg_website_pageviews)

       OR NOT EXISTS
       (SELECT 1 FROM ToyStore_StagingDB.dbo.stg_orders)

       OR NOT EXISTS
       (SELECT 1 FROM ToyStore_StagingDB.dbo.stg_order_items)

       OR NOT EXISTS
       (SELECT 1 FROM ToyStore_StagingDB.dbo.stg_products)

        THROW 50002,
        'Required staging tables are empty. Load the staging tables first.',
        1;


    BEGIN TRANSACTION;


 
    -- STEP 1 - CLEAN WEBSITE SESSION DATA
    

    SELECT
        s.website_session_id,

        s.user_id,

        YEAR(s.created_at) * 10000
            + MONTH(s.created_at) * 100
            + DAY(s.created_at) AS date_key,

        s.is_repeat_session,

        ISNULL(
            NULLIF(LTRIM(RTRIM(s.utm_source)), ''),
            'direct'
        ) AS utm_source,

        ISNULL(
            NULLIF(LTRIM(RTRIM(s.utm_campaign)), ''),
            'direct'
        ) AS utm_campaign,

        ISNULL(
            NULLIF(LTRIM(RTRIM(s.utm_content)), ''),
            'direct'
        ) AS utm_content,

        LTRIM(RTRIM(s.device_type)) AS device_type

    INTO #sess_clean

    FROM ToyStore_StagingDB.dbo.stg_website_sessions s;


    CREATE UNIQUE CLUSTERED INDEX ix_sess_clean
        ON #sess_clean (website_session_id);



    -- STEP 2 - LOAD DIM_DATE
   

    DECLARE @d0 DATE;
    DECLARE @d1 DATE;


    SELECT
        @d0 = MIN(d),
        @d1 = MAX(d)

    FROM
    (
        SELECT CAST(created_at AS DATE) AS d
        FROM ToyStore_StagingDB.dbo.stg_website_sessions

        UNION ALL

        SELECT CAST(created_at AS DATE)
        FROM ToyStore_StagingDB.dbo.stg_orders

        UNION ALL

        SELECT CAST(created_at AS DATE)
        FROM ToyStore_StagingDB.dbo.stg_order_items

    ) x;


    WITH cal AS
    (
        SELECT @d0 AS d

        UNION ALL

        SELECT DATEADD(DAY, 1, d)
        FROM cal
        WHERE d < @d1
    )

    INSERT INTO dbo.Dim_Date
    (
        date_key,
        full_date,
        day_num,
        month_num,
        month_name,
        quarter_num,
        year_num,
        day_of_week,
        is_weekend
    )

    SELECT
        YEAR(d) * 10000
            + MONTH(d) * 100
            + DAY(d),

        d,

        DAY(d),

        MONTH(d),

        DATENAME(MONTH, d),

        DATEPART(QUARTER, d),

        YEAR(d),

        DATENAME(WEEKDAY, d),

        CASE
            WHEN DATENAME(WEEKDAY, d)
                 IN ('Saturday', 'Sunday')
            THEN 1
            ELSE 0
        END

    FROM cal

    OPTION (MAXRECURSION 0);



    -- STEP 3 - LOAD DIM_PRODUCT
  

    INSERT INTO dbo.Dim_Product
    (
        product_id,
        product_name,
        launch_date
    )

    SELECT
        product_id,
        LTRIM(RTRIM(product_name)),
        CAST(created_at AS DATE)

    FROM ToyStore_StagingDB.dbo.stg_products;



    -- STEP 4 - LOAD DIM_CHANNEL
    
  

    INSERT INTO dbo.Dim_Channel
    (
        utm_source,
        utm_campaign,
        utm_content,
        device_type
    )

    SELECT DISTINCT
        utm_source,
        utm_campaign,
        utm_content,
        device_type

    FROM #sess_clean;



    -- STEP 5 - LOAD FACT_SESSIONS
    

    INSERT INTO dbo.Fact_Sessions
    (
        website_session_id,
        user_id,
        date_key,
        channel_key,
        pageview_count,
        is_repeat_session,
        converted_flag
    )

    SELECT
        sc.website_session_id,

        sc.user_id,

        sc.date_key,

        ch.channel_key,

        ISNULL(pv.pageviews, 0),

        sc.is_repeat_session,

        CASE
            WHEN o.website_session_id IS NULL
                THEN 0
            ELSE 1
        END

    FROM #sess_clean sc

    INNER JOIN dbo.Dim_Channel ch

        ON ch.utm_source = sc.utm_source

        AND ch.utm_campaign = sc.utm_campaign

        AND ch.utm_content = sc.utm_content

        AND ch.device_type = sc.device_type


    LEFT JOIN
    (
        SELECT
            website_session_id,
            COUNT(*) AS pageviews

        FROM ToyStore_StagingDB.dbo.stg_website_pageviews

        GROUP BY website_session_id

    ) pv

        ON pv.website_session_id = sc.website_session_id


    LEFT JOIN
    (
        SELECT DISTINCT
            website_session_id

        FROM ToyStore_StagingDB.dbo.stg_orders

    ) o

        ON o.website_session_id = sc.website_session_id;


  
    -- STEP 6 - LOAD FACT_ORDER_ITEMS
   

    INSERT INTO dbo.Fact_Order_Items
    (
        date_key,
        product_key,
        channel_key,
        order_id,
        website_session_id,
        user_id,
        is_primary_item,
        price_usd,
        cogs_usd,
        refund_amount_usd
    )

    SELECT

        YEAR(oi.created_at) * 10000
            + MONTH(oi.created_at) * 100
            + DAY(oi.created_at),

        p.product_key,

        ch.channel_key,

        oi.order_id,

        o.website_session_id,

        o.user_id,

        oi.is_primary_item,

        oi.price_usd,

        oi.cogs_usd,

        ISNULL(r.refund_usd, 0)

    FROM ToyStore_StagingDB.dbo.stg_order_items oi


    INNER JOIN ToyStore_StagingDB.dbo.stg_orders o

        ON o.order_id = oi.order_id


    INNER JOIN #sess_clean sc

        ON sc.website_session_id = o.website_session_id


    INNER JOIN dbo.Dim_Channel ch

        ON ch.utm_source = sc.utm_source

        AND ch.utm_campaign = sc.utm_campaign

        AND ch.utm_content = sc.utm_content

        AND ch.device_type = sc.device_type


    INNER JOIN dbo.Dim_Product p

        ON p.product_id = oi.product_id


    LEFT JOIN
    (
        SELECT
            order_item_id,
            SUM(refund_amount_usd) AS refund_usd

        FROM ToyStore_StagingDB.dbo.stg_order_item_refunds

        GROUP BY order_item_id

    ) r

        ON r.order_item_id = oi.order_item_id;



    -- STEP 7 - VALIDATION
   

    IF
    (
        SELECT COUNT(*)
        FROM dbo.Fact_Order_Items
    )
    <>
    (
        SELECT COUNT(*)
        FROM ToyStore_StagingDB.dbo.stg_order_items
    )

        THROW 50003,
        'Fact_Order_Items row count does not match stg_order_items. Load rolled back.',
        1;


    IF
    (
        SELECT COUNT(*)
        FROM dbo.Fact_Sessions
    )
    <>
    (
        SELECT COUNT(*)
        FROM ToyStore_StagingDB.dbo.stg_website_sessions
    )

        THROW 50004,
        'Fact_Sessions row count does not match stg_website_sessions. Load rolled back.',
        1;


    
    -- STEP 8 - COMMIT
    

    COMMIT TRANSACTION;

    PRINT 'Warehouse loaded from staging successfully.';


END TRY

BEGIN CATCH

    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    PRINT 'Load failed and was rolled back: '
          + ERROR_MESSAGE();

    THROW;

END CATCH;
GO



-- STEP 9 - WAREHOUSE ROW COUNT VALIDATION


SELECT
    'Dim_Date' AS table_name,
    COUNT(*) AS row_count
FROM dbo.Dim_Date

UNION ALL

SELECT
    'Dim_Product',
    COUNT(*)
FROM dbo.Dim_Product

UNION ALL

SELECT
    'Dim_Channel',
    COUNT(*)
FROM dbo.Dim_Channel

UNION ALL

SELECT
    'Fact_Order_Items',
    COUNT(*)
FROM dbo.Fact_Order_Items

UNION ALL

SELECT
    'Fact_Sessions',
    COUNT(*)
FROM dbo.Fact_Sessions;
GO



-- STEP 10 - BUSINESS MEASURE VALIDATION


SELECT

    (
        SELECT SUM(price_usd)
        FROM ToyStore_StagingDB.dbo.stg_order_items
    ) AS staging_revenue,

    (
        SELECT SUM(price_usd)
        FROM dbo.Fact_Order_Items
    ) AS warehouse_revenue,

    (
        SELECT SUM(refund_amount_usd)
        FROM ToyStore_StagingDB.dbo.stg_order_item_refunds
    ) AS staging_refunds,

    (
        SELECT SUM(refund_amount_usd)
        FROM dbo.Fact_Order_Items
    ) AS warehouse_refunds,

    (
        SELECT COUNT(*)
        FROM ToyStore_StagingDB.dbo.stg_website_pageviews
    ) AS staging_pageviews,

    (
        SELECT SUM(pageview_count)
        FROM dbo.Fact_Sessions
    ) AS warehouse_pageviews;
GO



-- STEP 11 - USER ID VALIDATION


SELECT
    COUNT(DISTINCT user_id) AS unique_session_users
FROM dbo.Fact_Sessions;

SELECT
    COUNT(DISTINCT user_id) AS unique_purchasing_users
FROM dbo.Fact_Order_Items;
GO