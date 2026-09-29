
-- 01_create_staging_tables.sql
-- Purpose: Create staging tables that mirror the raw source files
--          (CSV, Excel, JSON) before any transformation happens.

USE ToyStore_StagingDB;
GO

-- Drop existing staging tables if re-running this script
IF OBJECT_ID('stg_order_item_refunds', 'U') IS NOT NULL DROP TABLE stg_order_item_refunds;
IF OBJECT_ID('stg_order_items', 'U') IS NOT NULL DROP TABLE stg_order_items;
IF OBJECT_ID('stg_orders', 'U') IS NOT NULL DROP TABLE stg_orders;
IF OBJECT_ID('stg_website_pageviews', 'U') IS NOT NULL DROP TABLE stg_website_pageviews;
IF OBJECT_ID('stg_website_sessions', 'U') IS NOT NULL DROP TABLE stg_website_sessions;
IF OBJECT_ID('stg_products', 'U') IS NOT NULL DROP TABLE stg_products;
GO

-- Source: products.xlsx (Excel)
CREATE TABLE stg_products (
    product_id      INT PRIMARY KEY,
    created_at      DATETIME NOT NULL,
    product_name    VARCHAR(100) NOT NULL
);
GO

-- Source: website_sessions.json (JSON / web analytics)
CREATE TABLE stg_website_sessions (
    website_session_id INT PRIMARY KEY,
    created_at          DATETIME NOT NULL,
    user_id              INT NOT NULL,
    is_repeat_session    BIT NOT NULL,
    utm_source           VARCHAR(50) NULL,
    utm_campaign         VARCHAR(50) NULL,
    utm_content          VARCHAR(50) NULL,
    device_type          VARCHAR(20) NOT NULL,
    http_referer         VARCHAR(200) NULL
);
GO

-- Source: website_pageviews.json (JSON / web analytics)
CREATE TABLE stg_website_pageviews (
    website_pageview_id  INT PRIMARY KEY,
    created_at            DATETIME NOT NULL,
    website_session_id    INT NOT NULL,
    pageview_url          VARCHAR(200) NOT NULL,
    CONSTRAINT FK_pageviews_sessions FOREIGN KEY (website_session_id)
        REFERENCES stg_website_sessions(website_session_id)
);
GO

-- Source: orders.csv (transactional core)
CREATE TABLE stg_orders (
    order_id             INT PRIMARY KEY,
    created_at           DATETIME NOT NULL,
    website_session_id   INT NOT NULL,
    user_id              INT NOT NULL,
    primary_product_id   INT NOT NULL,
    items_purchased      INT NOT NULL,
    price_usd            DECIMAL(10,2) NOT NULL,
    cogs_usd             DECIMAL(10,2) NOT NULL,
    CONSTRAINT FK_orders_sessions FOREIGN KEY (website_session_id)
        REFERENCES stg_website_sessions(website_session_id),
    CONSTRAINT FK_orders_products FOREIGN KEY (primary_product_id)
        REFERENCES stg_products(product_id)
);
GO

-- Source: order_items.csv (transactional core)
CREATE TABLE stg_order_items (
    order_item_id     INT PRIMARY KEY,
    created_at        DATETIME NOT NULL,
    order_id          INT NOT NULL,
    product_id        INT NOT NULL,
    is_primary_item   BIT NOT NULL,
    price_usd         DECIMAL(10,2) NOT NULL,
    cogs_usd          DECIMAL(10,2) NOT NULL,
    CONSTRAINT FK_orderitems_orders FOREIGN KEY (order_id)
        REFERENCES stg_orders(order_id),
    CONSTRAINT FK_orderitems_products FOREIGN KEY (product_id)
        REFERENCES stg_products(product_id)
);
GO

-- Source: order_item_refunds.csv (transactional core)
CREATE TABLE stg_order_item_refunds (
    order_item_refund_id  INT PRIMARY KEY,
    created_at             DATETIME NOT NULL,
    order_item_id          INT NOT NULL,
    order_id               INT NOT NULL,
    refund_amount_usd      DECIMAL(10,2) NOT NULL,
    CONSTRAINT FK_refunds_orderitems FOREIGN KEY (order_item_id)
        REFERENCES stg_order_items(order_item_id),
    CONSTRAINT FK_refunds_orders FOREIGN KEY (order_id)
        REFERENCES stg_orders(order_id)
);
GO

PRINT 'Staging tables created successfully.';