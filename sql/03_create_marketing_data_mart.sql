 
-- 03_create_marketing_data_mart.sql
-- Purpose: Build the Marketing Performance data mart.
--          A department specific summary of the warehouse for the
--          marketing team: one row per day per marketing channel.


USE ToyStore_WarehouseDB;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'mart')
    EXEC('CREATE SCHEMA mart');
GO

IF OBJECT_ID('mart.vw_Channel_Performance', 'V') IS NOT NULL DROP VIEW mart.vw_Channel_Performance;
IF OBJECT_ID('mart.Marketing_Performance', 'U') IS NOT NULL DROP TABLE mart.Marketing_Performance;
GO


-- Mart table. Grain: one row per date per channel.
 
 
CREATE TABLE mart.Marketing_Performance (
    date_key             INT           NOT NULL,
    channel_key          INT           NOT NULL,
    full_date            DATE          NOT NULL,
    month_name           VARCHAR(20)   NOT NULL,
    month_num            INT           NOT NULL,
    quarter_num          INT           NOT NULL,
    year_num             INT           NOT NULL,
    utm_source           VARCHAR(50)   NOT NULL,
    utm_campaign         VARCHAR(50)   NOT NULL,
    utm_content          VARCHAR(50)   NOT NULL,
    device_type          VARCHAR(20)   NOT NULL,
    sessions             INT           NOT NULL,
    repeat_sessions      INT           NOT NULL,
    converted_sessions   INT           NOT NULL,
    pageviews            INT           NOT NULL,
    orders               INT           NOT NULL,
    items_sold           INT           NOT NULL,
    revenue_usd          DECIMAL(12,2) NOT NULL,
    cogs_usd             DECIMAL(12,2) NOT NULL,
    refund_usd           DECIMAL(12,2) NOT NULL,
    CONSTRAINT PK_Marketing_Performance PRIMARY KEY (date_key, channel_key),
    CONSTRAINT FK_mart_date    FOREIGN KEY (date_key)    REFERENCES dbo.Dim_Date(date_key),
    CONSTRAINT FK_mart_channel FOREIGN KEY (channel_key) REFERENCES dbo.Dim_Channel(channel_key)
);
GO

 
-- Load the mart from the warehouse fact tables.
 
WITH s AS (
    SELECT date_key, channel_key,
           COUNT(*)                            AS sessions,
           SUM(CAST(is_repeat_session AS INT)) AS repeat_sessions,
           SUM(CAST(converted_flag AS INT))    AS converted_sessions,
           SUM(pageview_count)                 AS pageviews
    FROM dbo.Fact_Sessions
    GROUP BY date_key, channel_key
),
o AS (
    SELECT date_key, channel_key,
           COUNT(DISTINCT order_id)  AS orders,
           COUNT(*)                  AS items_sold,
           SUM(price_usd)            AS revenue_usd,
           SUM(cogs_usd)             AS cogs_usd,
           SUM(refund_amount_usd)    AS refund_usd
    FROM dbo.Fact_Order_Items
    GROUP BY date_key, channel_key
)
INSERT INTO mart.Marketing_Performance
    (date_key, channel_key, full_date, month_name, month_num, quarter_num, year_num,
     utm_source, utm_campaign, utm_content, device_type,
     sessions, repeat_sessions, converted_sessions, pageviews,
     orders, items_sold, revenue_usd, cogs_usd, refund_usd)
SELECT
    COALESCE(s.date_key, o.date_key),
    COALESCE(s.channel_key, o.channel_key),
    d.full_date, d.month_name, d.month_num, d.quarter_num, d.year_num,
    c.utm_source, c.utm_campaign, c.utm_content, c.device_type,
    ISNULL(s.sessions, 0),
    ISNULL(s.repeat_sessions, 0),
    ISNULL(s.converted_sessions, 0),
    ISNULL(s.pageviews, 0),
    ISNULL(o.orders, 0),
    ISNULL(o.items_sold, 0),
    ISNULL(o.revenue_usd, 0),
    ISNULL(o.cogs_usd, 0),
    ISNULL(o.refund_usd, 0)
FROM s
FULL OUTER JOIN o
    ON s.date_key = o.date_key AND s.channel_key = o.channel_key
JOIN dbo.Dim_Date d
    ON d.date_key = COALESCE(s.date_key, o.date_key)
JOIN dbo.Dim_Channel c
    ON c.channel_key = COALESCE(s.channel_key, o.channel_key);
GO

 -- View with the ratio measures (summed totals)
 
CREATE VIEW mart.vw_Channel_Performance AS
SELECT
    date_key, channel_key, full_date, month_name, month_num, quarter_num, year_num,
    utm_source, utm_campaign, utm_content, device_type,
    sessions, repeat_sessions, converted_sessions, pageviews,
    orders, items_sold, revenue_usd, cogs_usd, refund_usd,
    revenue_usd - refund_usd                                        AS net_revenue_usd,
    revenue_usd - cogs_usd                                          AS gross_profit_usd,
    CAST(100.0 * converted_sessions / NULLIF(sessions, 0) AS DECIMAL(6,2))  AS conversion_rate_pct,
    CAST(revenue_usd / NULLIF(sessions, 0) AS DECIMAL(10,4))        AS revenue_per_session,
    CAST(revenue_usd / NULLIF(orders, 0)   AS DECIMAL(10,2))        AS avg_order_value,
    CAST(100.0 * refund_usd / NULLIF(revenue_usd, 0) AS DECIMAL(6,2)) AS refund_rate_pct
FROM mart.Marketing_Performance;
GO

PRINT 'Marketing Performance data mart created and loaded.';
GO
