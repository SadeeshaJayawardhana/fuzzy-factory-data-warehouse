USE ToyStore_WarehouseDB;
GO



-- Drop existing warehouse tables (if re-running this script)
=

IF OBJECT_ID('Fact_Sessions', 'U') IS NOT NULL
    DROP TABLE Fact_Sessions;

IF OBJECT_ID('Fact_Order_Items', 'U') IS NOT NULL
    DROP TABLE Fact_Order_Items;

IF OBJECT_ID('Dim_Channel', 'U') IS NOT NULL
    DROP TABLE Dim_Channel;

IF OBJECT_ID('Dim_Product', 'U') IS NOT NULL
    DROP TABLE Dim_Product;

IF OBJECT_ID('Dim_Date', 'U') IS NOT NULL
    DROP TABLE Dim_Date;
GO


-- Dim_Date


CREATE TABLE Dim_Date
(
    date_key      INT PRIMARY KEY,       
    full_date     DATE NOT NULL,
    day_num       INT NOT NULL,
    month_num     INT NOT NULL,
    month_name    VARCHAR(20) NOT NULL,
    quarter_num   INT NOT NULL,
    year_num      INT NOT NULL,
    day_of_week   VARCHAR(10) NOT NULL,
    is_weekend    BIT NOT NULL
);
GO


-- Dim_Product


CREATE TABLE Dim_Product
(
    product_key    INT IDENTITY(1,1) PRIMARY KEY,
    product_id     INT NOT NULL,         
    product_name   VARCHAR(100) NOT NULL,
    launch_date    DATE NOT NULL
);
GO



-- Dim_Channel

CREATE TABLE Dim_Channel
(
    channel_key    INT IDENTITY(1,1) PRIMARY KEY,
    utm_source     VARCHAR(50) NOT NULL,   
    utm_campaign   VARCHAR(50) NOT NULL,  
    utm_content    VARCHAR(50) NOT NULL,  
    device_type    VARCHAR(20) NOT NULL
);
GO


-- Fact_Order_Items


CREATE TABLE Fact_Order_Items
(
    order_item_key       INT IDENTITY(1,1) PRIMARY KEY,

    date_key             INT NOT NULL,
    product_key          INT NOT NULL,
    channel_key          INT NOT NULL,

    order_id             INT NOT NULL,     
    website_session_id   INT NOT NULL,     
    user_id              INT NOT NULL,     

    is_primary_item      BIT NOT NULL,

    price_usd            DECIMAL(10,2) NOT NULL,
    cogs_usd             DECIMAL(10,2) NOT NULL,
    refund_amount_usd    DECIMAL(10,2) NOT NULL DEFAULT 0,

    CONSTRAINT FK_factorderitems_date
        FOREIGN KEY (date_key)
        REFERENCES Dim_Date(date_key),

    CONSTRAINT FK_factorderitems_product
        FOREIGN KEY (product_key)
        REFERENCES Dim_Product(product_key),

    CONSTRAINT FK_factorderitems_channel
        FOREIGN KEY (channel_key)
        REFERENCES Dim_Channel(channel_key)
);
GO



-- Fact_Sessions


CREATE TABLE Fact_Sessions
(
    session_key          INT IDENTITY(1,1) PRIMARY KEY,

    website_session_id   INT NOT NULL,     
    user_id              INT NOT NULL,     

    date_key             INT NOT NULL,
    channel_key          INT NOT NULL,

    pageview_count       INT NOT NULL DEFAULT 0,
    is_repeat_session    BIT NOT NULL,
    converted_flag       BIT NOT NULL DEFAULT 0,

    CONSTRAINT FK_factsessions_date
        FOREIGN KEY (date_key)
        REFERENCES Dim_Date(date_key),

    CONSTRAINT FK_factsessions_channel
        FOREIGN KEY (channel_key)
        REFERENCES Dim_Channel(channel_key)
);
GO


PRINT 'Warehouse (star schema) tables created successfully.';
GO