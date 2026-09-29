import pandas as pd
import pyodbc

SERVER = "SADEE"
DRIVER = "ODBC Driver 17 for SQL Server"

SOURCE_DIR = "../sources"


def connect(db_name):
    conn_str = f"DRIVER={{{DRIVER}}};SERVER={SERVER};DATABASE={db_name};Trusted_Connection=yes;"
    return pyodbc.connect(conn_str)


def insert_rows(cursor, table, df, columns, has_identity=False):
    if has_identity:
        cursor.execute(f"SET IDENTITY_INSERT {table} ON")

    placeholders = ",".join("?" * len(columns))
    sql = f"INSERT INTO {table} ({','.join(columns)}) VALUES ({placeholders})"

    # pandas can store empty values as NaN, NaT or pd.NA depending on the
    # column type, and pyodbc chokes on those, so swap them for plain None
    rows = [
        tuple(None if pd.isna(v) else v for v in r)
        for r in df[columns].itertuples(index=False, name=None)
    ]

    cursor.fast_executemany = True
    cursor.executemany(sql, rows)

    if has_identity:
        cursor.execute(f"SET IDENTITY_INSERT {table} OFF")

    print(f"{table}: inserted {len(rows)} rows")


# ---------- read the source files ----------

orders = pd.read_csv(f"{SOURCE_DIR}/orders.csv")
order_items = pd.read_csv(f"{SOURCE_DIR}/order_items.csv")
refunds = pd.read_csv(f"{SOURCE_DIR}/order_item_refunds.csv")
products = pd.read_excel(f"{SOURCE_DIR}/products.xlsx")
sessions = pd.read_json(f"{SOURCE_DIR}/website_sessions.json")
pageviews = pd.read_json(f"{SOURCE_DIR}/website_pageviews.json")

# fix date columns
for df in [orders, order_items, refunds, products, sessions, pageviews]:
    df["created_at"] = pd.to_datetime(df["created_at"])

# empty utm values just mean direct/organic traffic, not missing data
sessions[["utm_source", "utm_campaign", "utm_content"]] = \
    sessions[["utm_source", "utm_campaign", "utm_content"]].fillna("direct")

orders = orders.drop_duplicates(subset="order_id")
order_items = order_items.drop_duplicates(subset="order_item_id")
sessions = sessions.drop_duplicates(subset="website_session_id")
products = products.drop_duplicates(subset="product_id")

for df in [orders, order_items]:
    df["price_usd"] = df["price_usd"].round(2)
    df["cogs_usd"] = df["cogs_usd"].round(2)
refunds["refund_amount_usd"] = refunds["refund_amount_usd"].round(2)

print("source files loaded and cleaned")


# ---------- load staging tables ----------

stg_conn = connect("ToyStore_StagingDB")
stg_cur = stg_conn.cursor()

# delete children before parents
for t in ["stg_order_item_refunds", "stg_order_items", "stg_orders",
          "stg_website_pageviews", "stg_website_sessions", "stg_products"]:
    stg_cur.execute(f"DELETE FROM {t}")
stg_conn.commit()

insert_rows(stg_cur, "stg_products", products,
    ["product_id", "created_at", "product_name"])

insert_rows(stg_cur, "stg_website_sessions", sessions,
    ["website_session_id", "created_at", "user_id", "is_repeat_session",
     "utm_source", "utm_campaign", "utm_content", "device_type", "http_referer"])

insert_rows(stg_cur, "stg_website_pageviews", pageviews,
    ["website_pageview_id", "created_at", "website_session_id", "pageview_url"])

insert_rows(stg_cur, "stg_orders", orders,
    ["order_id", "created_at", "website_session_id", "user_id",
     "primary_product_id", "items_purchased", "price_usd", "cogs_usd"])

insert_rows(stg_cur, "stg_order_items", order_items,
    ["order_item_id", "created_at", "order_id", "product_id",
     "is_primary_item", "price_usd", "cogs_usd"])

insert_rows(stg_cur, "stg_order_item_refunds", refunds,
    ["order_item_refund_id", "created_at", "order_item_id", "order_id", "refund_amount_usd"])

stg_conn.commit()
stg_conn.close()
print("staging load done\n")


# ---------- read staging tables back out ----------

stg_conn = connect("ToyStore_StagingDB")
orders = pd.read_sql("SELECT * FROM stg_orders", stg_conn)
order_items = pd.read_sql("SELECT * FROM stg_order_items", stg_conn)
refunds = pd.read_sql("SELECT * FROM stg_order_item_refunds", stg_conn)
products = pd.read_sql("SELECT * FROM stg_products", stg_conn)
sessions = pd.read_sql("SELECT * FROM stg_website_sessions", stg_conn)
pageviews = pd.read_sql("SELECT * FROM stg_website_pageviews", stg_conn)
stg_conn.close()

print("read staging tables back:", len(orders), "orders,", len(sessions), "sessions")


# ---------- build the dimension and fact tables ----------

# Dim_Date
all_dates = pd.concat([orders["created_at"], sessions["created_at"]]).dt.normalize()
dim_date = pd.DataFrame({"full_date": pd.date_range(all_dates.min(), all_dates.max())})
dim_date["date_key"] = dim_date["full_date"].dt.strftime("%Y%m%d").astype(int)
dim_date["day_num"] = dim_date["full_date"].dt.day
dim_date["month_num"] = dim_date["full_date"].dt.month
dim_date["month_name"] = dim_date["full_date"].dt.month_name()
dim_date["quarter_num"] = dim_date["full_date"].dt.quarter
dim_date["year_num"] = dim_date["full_date"].dt.year
dim_date["day_of_week"] = dim_date["full_date"].dt.day_name()
dim_date["is_weekend"] = dim_date["full_date"].dt.dayofweek.isin([5, 6]).astype(int)

# Dim_Product
dim_product = products.reset_index(drop=True)
dim_product["product_key"] = dim_product.index + 1
dim_product = dim_product.rename(columns={"created_at": "launch_date"})
dim_product["launch_date"] = dim_product["launch_date"].dt.date

# Dim_Channel
dim_channel = sessions[["utm_source", "utm_campaign", "utm_content", "device_type"]] \
    .drop_duplicates().reset_index(drop=True)
dim_channel["channel_key"] = dim_channel.index + 1

sessions = sessions.merge(dim_channel, on=["utm_source", "utm_campaign", "utm_content", "device_type"])
sessions["date_key"] = sessions["created_at"].dt.strftime("%Y%m%d").astype(int)

# Fact_Order_Items
refund_by_item = refunds.groupby("order_item_id")["refund_amount_usd"].sum().reset_index()

fact_order_items = order_items \
    .merge(orders[["order_id", "website_session_id"]], on="order_id") \
    .merge(sessions[["website_session_id", "channel_key"]], on="website_session_id") \
    .merge(dim_product[["product_id", "product_key"]], on="product_id") \
    .merge(refund_by_item, on="order_item_id", how="left")

fact_order_items["refund_amount_usd"] = fact_order_items["refund_amount_usd"].fillna(0).round(2)
fact_order_items["date_key"] = fact_order_items["created_at"].dt.strftime("%Y%m%d").astype(int)
fact_order_items["order_item_key"] = fact_order_items.index + 1

# Fact_Sessions
pageview_counts = pageviews.groupby("website_session_id").size().reset_index(name="pageview_count")
converted_ids = set(orders["website_session_id"])

fact_sessions = sessions.merge(pageview_counts, on="website_session_id", how="left")
fact_sessions["pageview_count"] = fact_sessions["pageview_count"].fillna(0).astype(int)
fact_sessions["converted_flag"] = fact_sessions["website_session_id"].isin(converted_ids).astype(int)
fact_sessions["session_key"] = fact_sessions.index + 1

print("dimensions and facts built:")
print("  Dim_Date:", len(dim_date))
print("  Dim_Product:", len(dim_product))
print("  Dim_Channel:", len(dim_channel))
print("  Fact_Order_Items:", len(fact_order_items))
print("  Fact_Sessions:", len(fact_sessions))

missing_keys = fact_order_items["channel_key"].isnull().sum() + fact_order_items["product_key"].isnull().sum()
print("  Fact_Order_Items rows missing a key:", missing_keys, "(should be 0)\n")


# ---------- load the warehouse tables ----------

wh_conn = connect("ToyStore_WarehouseDB")
wh_cur = wh_conn.cursor()

for t in ["Fact_Order_Items", "Fact_Sessions", "Dim_Product", "Dim_Channel", "Dim_Date"]:
    wh_cur.execute(f"DELETE FROM {t}")
wh_conn.commit()

insert_rows(wh_cur, "Dim_Date", dim_date,
    ["date_key", "full_date", "day_num", "month_num", "month_name",
     "quarter_num", "year_num", "day_of_week", "is_weekend"])

insert_rows(wh_cur, "Dim_Product", dim_product,
    ["product_key", "product_id", "product_name", "launch_date"], has_identity=True)

insert_rows(wh_cur, "Dim_Channel", dim_channel,
    ["channel_key", "utm_source", "utm_campaign", "utm_content", "device_type"], has_identity=True)

insert_rows(wh_cur, "Fact_Order_Items", fact_order_items,
    ["order_item_key", "date_key", "product_key", "channel_key", "order_id",
     "website_session_id", "is_primary_item", "price_usd", "cogs_usd", "refund_amount_usd"],
    has_identity=True)

insert_rows(wh_cur, "Fact_Sessions", fact_sessions,
    ["session_key", "website_session_id", "date_key", "channel_key",
     "pageview_count", "is_repeat_session", "converted_flag"], has_identity=True)

wh_conn.commit()
wh_conn.close()
print("warehouse load done")
