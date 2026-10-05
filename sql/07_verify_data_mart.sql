
USE ToyStore_WarehouseDB;
GO

SET NOCOUNT ON;
GO



-- CHECK 1 - MART ROW COUNT AND TOTALS


SELECT

    COUNT(*) AS mart_rows,

    SUM(sessions) AS sessions,

    SUM(repeat_sessions) AS repeat_sessions,

    SUM(converted_sessions) AS converted_sessions,

    SUM(pageviews) AS pageviews,

    SUM(orders) AS orders,

    SUM(items_sold) AS items_sold,

    SUM(revenue_usd) AS revenue_usd,

    SUM(cogs_usd) AS cogs_usd,

    SUM(refund_usd) AS refund_usd

FROM mart.Marketing_Performance;
GO



-- CHECK 2 - SESSION RECONCILIATION

SELECT

    (
        SELECT SUM(sessions)
        FROM mart.Marketing_Performance
    ) AS mart_sessions,

    (
        SELECT COUNT(*)
        FROM dbo.Fact_Sessions
    ) AS fact_sessions,


    (
        SELECT SUM(repeat_sessions)
        FROM mart.Marketing_Performance
    ) AS mart_repeat_sessions,

    (
        SELECT SUM(CAST(is_repeat_session AS INT))
        FROM dbo.Fact_Sessions
    ) AS fact_repeat_sessions,


    (
        SELECT SUM(converted_sessions)
        FROM mart.Marketing_Performance
    ) AS mart_converted_sessions,

    (
        SELECT SUM(CAST(converted_flag AS INT))
        FROM dbo.Fact_Sessions
    ) AS fact_converted_sessions,


    (
        SELECT SUM(pageviews)
        FROM mart.Marketing_Performance
    ) AS mart_pageviews,

    (
        SELECT SUM(pageview_count)
        FROM dbo.Fact_Sessions
    ) AS fact_pageviews;
GO



-- CHECK 3 - SALES RECONCILIATION


SELECT

    (
        SELECT SUM(orders)
        FROM mart.Marketing_Performance
    ) AS mart_orders,

    (
        SELECT COUNT(DISTINCT order_id)
        FROM dbo.Fact_Order_Items
    ) AS fact_orders,


    (
        SELECT SUM(items_sold)
        FROM mart.Marketing_Performance
    ) AS mart_items,

    (
        SELECT COUNT(*)
        FROM dbo.Fact_Order_Items
    ) AS fact_items,


    (
        SELECT SUM(revenue_usd)
        FROM mart.Marketing_Performance
    ) AS mart_revenue,

    (
        SELECT SUM(price_usd)
        FROM dbo.Fact_Order_Items
    ) AS fact_revenue,


    (
        SELECT SUM(cogs_usd)
        FROM mart.Marketing_Performance
    ) AS mart_cogs,

    (
        SELECT SUM(cogs_usd)
        FROM dbo.Fact_Order_Items
    ) AS fact_cogs,


    (
        SELECT SUM(refund_usd)
        FROM mart.Marketing_Performance
    ) AS mart_refunds,

    (
        SELECT SUM(refund_amount_usd)
        FROM dbo.Fact_Order_Items
    ) AS fact_refunds;
GO



-- CHECK 4 - CHECK FOR DUPLICATE MART GRAIN


SELECT

    date_key,
    channel_key,
    COUNT(*) AS duplicate_count

FROM mart.Marketing_Performance

GROUP BY
    date_key,
    channel_key

HAVING COUNT(*) > 1;
GO



-- CHECK 5 - CHECK FOR NEGATIVE OR IMPOSSIBLE VALUES


SELECT *

FROM mart.Marketing_Performance

WHERE
       sessions < 0
    OR repeat_sessions < 0
    OR converted_sessions < 0
    OR pageviews < 0
    OR orders < 0
    OR items_sold < 0
    OR revenue_usd < 0
    OR cogs_usd < 0
    OR refund_usd < 0

    OR converted_sessions > sessions
    OR repeat_sessions > sessions;
GO



-- CHECK 6 - SAMPLE CHANNEL PERFORMANCE ANALYSIS


SELECT

    utm_source,

    SUM(sessions) AS sessions,

    SUM(converted_sessions) AS converted_sessions,

    SUM(orders) AS orders,

    CAST
    (
        100.0 * SUM(converted_sessions)
        / NULLIF(SUM(sessions), 0)

        AS DECIMAL(6,2)
    ) AS conversion_rate_pct,

    SUM(revenue_usd) AS revenue_usd,

    SUM(refund_usd) AS refund_usd,

    CAST
    (
        SUM(revenue_usd)
        / NULLIF(CAST(SUM(sessions) AS DECIMAL(18,4)), 0)

        AS DECIMAL(12,4)
    ) AS revenue_per_session

FROM mart.Marketing_Performance

GROUP BY utm_source

ORDER BY revenue_usd DESC;
GO



-- CHECK 7 - MONTHLY TREND


SELECT

    year_num,

    month_num,

    month_name,

    SUM(sessions) AS sessions,

    SUM(converted_sessions) AS converted_sessions,

    SUM(orders) AS orders,

    SUM(items_sold) AS items_sold,

    SUM(revenue_usd) AS revenue_usd,

    SUM(refund_usd) AS refund_usd

FROM mart.Marketing_Performance

GROUP BY
    year_num,
    month_num,
    month_name

ORDER BY
    year_num,
    month_num;
GO



-- CHECK 8 - TEST ANALYTICAL VIEW


SELECT TOP 10

    full_date,

    utm_source,

    utm_campaign,

    device_type,

    sessions,

    orders,

    revenue_usd,

    net_revenue_usd,

    gross_profit_usd,

    profit_after_refunds_usd,

    conversion_rate_pct,

    revenue_per_session,

    avg_order_value,

    refund_rate_pct,

    pages_per_session

FROM mart.vw_Channel_Performance

ORDER BY revenue_usd DESC;
GO


PRINT 'Marketing Performance data mart verification completed.';
GO