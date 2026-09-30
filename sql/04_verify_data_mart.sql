
-- 04_verify_data_mart.sql
 

USE ToyStore_WarehouseDB;
GO

-- 1. Row count and totals. 

SELECT COUNT(*)                 AS mart_rows,
       SUM(sessions)            AS sessions,
       SUM(converted_sessions)  AS converted_sessions,
       SUM(pageviews)           AS pageviews,
       SUM(orders)              AS orders,
       SUM(items_sold)          AS items_sold,
       SUM(revenue_usd)         AS revenue_usd,
       SUM(cogs_usd)            AS cogs_usd,
       SUM(refund_usd)          AS refund_usd
FROM mart.Marketing_Performance;

-- 2. Reconcile the mart against the fact tables. Each pair must match.
SELECT
  (SELECT SUM(sessions)    FROM mart.Marketing_Performance) AS mart_sessions,
  (SELECT COUNT(*)         FROM dbo.Fact_Sessions)          AS fact_sessions,
  (SELECT SUM(revenue_usd) FROM mart.Marketing_Performance) AS mart_revenue,
  (SELECT SUM(price_usd)   FROM dbo.Fact_Order_Items)       AS fact_revenue;

-- 3. Sample analysis 1: channel performance  

SELECT utm_source,
       SUM(sessions)                                   AS sessions,
       SUM(orders)                                     AS orders,
       CAST(100.0 * SUM(converted_sessions) / SUM(sessions) AS DECIMAL(6,2)) AS conversion_rate_pct,
       SUM(revenue_usd)                                AS revenue_usd,
       CAST(SUM(revenue_usd) / SUM(sessions) AS DECIMAL(10,4)) AS revenue_per_session
FROM mart.Marketing_Performance
GROUP BY utm_source
ORDER BY revenue_usd DESC;

-- 4. Sample analysis 2: monthly trend (roll-up from day to month).
SELECT year_num, month_num, month_name,
       SUM(sessions)    AS sessions,
       SUM(orders)      AS orders,
       SUM(revenue_usd) AS revenue_usd
FROM mart.Marketing_Performance
GROUP BY year_num, month_num, month_name
ORDER BY year_num, month_num;

-- 5. The view with the ratios already worked out.
SELECT TOP 10 full_date, utm_source, device_type, sessions, orders,
       conversion_rate_pct, revenue_per_session, avg_order_value
FROM mart.vw_Channel_Performance
ORDER BY revenue_usd DESC;
GO
