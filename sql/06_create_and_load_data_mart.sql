
USE ToyStore_WarehouseDB;
GO

SET NOCOUNT ON;
GO



-- STEP 1 - CREATE MART SCHEMA


IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = 'mart'
)
BEGIN
    EXEC('CREATE SCHEMA mart');
END;
GO


-- STEP 2 - DROP EXISTING MART OBJECTS


IF OBJECT_ID('mart.vw_Channel_Performance', 'V') IS NOT NULL
    DROP VIEW mart.vw_Channel_Performance;
GO

IF OBJECT_ID('mart.Marketing_Performance', 'U') IS NOT NULL
    DROP TABLE mart.Marketing_Performance;
GO



-- STEP 3 - CREATE MARKETING PERFORMANCE MART TABLE

CREATE TABLE mart.Marketing_Performance
(
   
    -- Keys
   

    date_key             INT           NOT NULL,
    channel_key          INT           NOT NULL,


  
    -- Date attributes
  

    full_date            DATE          NOT NULL,
    month_name           VARCHAR(20)   NOT NULL,
    month_num            INT           NOT NULL,
    quarter_num          INT           NOT NULL,
    year_num             INT           NOT NULL,


  
    -- Marketing channel attributes
  

    utm_source           VARCHAR(50)   NOT NULL,
    utm_campaign         VARCHAR(50)   NOT NULL,
    utm_content          VARCHAR(50)   NOT NULL,
    device_type          VARCHAR(20)   NOT NULL,


   
    -- Website / session measures
    

    sessions             INT           NOT NULL,
    repeat_sessions      INT           NOT NULL,
    converted_sessions   INT           NOT NULL,
    pageviews            INT           NOT NULL,


    
    -- Sales measures
   

    orders               INT           NOT NULL,
    items_sold           INT           NOT NULL,


   
    -- Financial measures
    

    revenue_usd          DECIMAL(12,2) NOT NULL,
    cogs_usd             DECIMAL(12,2) NOT NULL,
    refund_usd           DECIMAL(12,2) NOT NULL,


    -
    -- Constraints
    

    CONSTRAINT PK_Marketing_Performance
        PRIMARY KEY (date_key, channel_key),

    CONSTRAINT FK_mart_date
        FOREIGN KEY (date_key)
        REFERENCES dbo.Dim_Date(date_key),

    CONSTRAINT FK_mart_channel
        FOREIGN KEY (channel_key)
        REFERENCES dbo.Dim_Channel(channel_key)
);
GO



-- STEP 4 - AGGREGATE AND LOAD THE DATA MART


WITH SessionSummary AS
(
    SELECT
        date_key,
        channel_key,

        COUNT(*) AS sessions,

        SUM(CAST(is_repeat_session AS INT))
            AS repeat_sessions,

        SUM(CAST(converted_flag AS INT))
            AS converted_sessions,

        SUM(pageview_count)
            AS pageviews

    FROM dbo.Fact_Sessions

    GROUP BY
        date_key,
        channel_key
),

OrderSummary AS
(
    SELECT
        date_key,
        channel_key,

        COUNT(DISTINCT order_id)
            AS orders,

        COUNT(*)
            AS items_sold,

        SUM(price_usd)
            AS revenue_usd,

        SUM(cogs_usd)
            AS cogs_usd,

        SUM(refund_amount_usd)
            AS refund_usd

    FROM dbo.Fact_Order_Items

    GROUP BY
        date_key,
        channel_key
)


INSERT INTO mart.Marketing_Performance
(
    date_key,
    channel_key,

    full_date,
    month_name,
    month_num,
    quarter_num,
    year_num,

    utm_source,
    utm_campaign,
    utm_content,
    device_type,

    sessions,
    repeat_sessions,
    converted_sessions,
    pageviews,

    orders,
    items_sold,

    revenue_usd,
    cogs_usd,
    refund_usd
)

SELECT

    COALESCE(s.date_key, o.date_key)
        AS date_key,

    COALESCE(s.channel_key, o.channel_key)
        AS channel_key,


    -- Date attributes

    d.full_date,
    d.month_name,
    d.month_num,
    d.quarter_num,
    d.year_num,


    -- Channel attributes

    c.utm_source,
    c.utm_campaign,
    c.utm_content,
    c.device_type,


    -- Session measures

    ISNULL(s.sessions, 0)
        AS sessions,

    ISNULL(s.repeat_sessions, 0)
        AS repeat_sessions,

    ISNULL(s.converted_sessions, 0)
        AS converted_sessions,

    ISNULL(s.pageviews, 0)
        AS pageviews,


    -- Sales measures

    ISNULL(o.orders, 0)
        AS orders,

    ISNULL(o.items_sold, 0)
        AS items_sold,


    -- Financial measures

    ISNULL(o.revenue_usd, 0)
        AS revenue_usd,

    ISNULL(o.cogs_usd, 0)
        AS cogs_usd,

    ISNULL(o.refund_usd, 0)
        AS refund_usd


FROM SessionSummary s

FULL OUTER JOIN OrderSummary o

    ON s.date_key = o.date_key
    AND s.channel_key = o.channel_key


INNER JOIN dbo.Dim_Date d

    ON d.date_key =
       COALESCE(s.date_key, o.date_key)


INNER JOIN dbo.Dim_Channel c

    ON c.channel_key =
       COALESCE(s.channel_key, o.channel_key);
GO



-- STEP 5 - CREATE ANALYTICAL VIEW


CREATE VIEW mart.vw_Channel_Performance
AS

SELECT

    -- Keys
    date_key,
    channel_key,


    -- Date attributes
    full_date,
    month_name,
    month_num,
    quarter_num,
    year_num,


    -- Channel attributes
    utm_source,
    utm_campaign,
    utm_content,
    device_type,


    -- Base measures
    sessions,
    repeat_sessions,
    converted_sessions,
    pageviews,

    orders,
    items_sold,

    revenue_usd,
    cogs_usd,
    refund_usd,


   
    -- Derived financial measures
   

    revenue_usd - refund_usd
        AS net_revenue_usd,

    revenue_usd - cogs_usd
        AS gross_profit_usd,

    revenue_usd - refund_usd - cogs_usd
        AS profit_after_refunds_usd,


    
    -- Marketing / sales ratios
   

    CAST
    (
        100.0 * converted_sessions
        / NULLIF(sessions, 0)

        AS DECIMAL(6,2)
    ) AS conversion_rate_pct,


    CAST
    (
        revenue_usd
        / NULLIF(CAST(sessions AS DECIMAL(18,4)), 0)

        AS DECIMAL(12,4)
    ) AS revenue_per_session,


    CAST
    (
        revenue_usd
        / NULLIF(CAST(orders AS DECIMAL(18,4)), 0)

        AS DECIMAL(12,2)
    ) AS avg_order_value,


    CAST
    (
        100.0 * refund_usd
        / NULLIF(revenue_usd, 0)

        AS DECIMAL(6,2)
    ) AS refund_rate_pct,


    CAST
    (
        pageviews
        / NULLIF(CAST(sessions AS DECIMAL(18,4)), 0)

        AS DECIMAL(12,2)
    ) AS pages_per_session


FROM mart.Marketing_Performance;
GO



-- STEP 6 - COMPLETION MESSAGE


PRINT 'Marketing Performance data mart created and loaded successfully.';
GO