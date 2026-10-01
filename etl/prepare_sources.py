import pandas as pd
import os

RAW = "../raw_data/"
OUT = "../sources/"

os.makedirs(OUT, exist_ok=True)

orders = pd.read_csv(RAW + "orders.csv")
order_items = pd.read_csv(RAW + "order_items.csv")
refunds = pd.read_csv(RAW + "order_item_refunds.csv")
products = pd.read_csv(RAW + "products.csv")
sessions = pd.read_csv(RAW + "website_sessions.csv")
pageviews = pd.read_csv(RAW + "website_pageviews.csv")

print("orders:", len(orders))
print("order_items:", len(order_items))
print("refunds:", len(refunds))
print("products:", len(products))
print("sessions:", len(sessions))
print("pageviews:", len(pageviews))

# CSV: transactional core
orders.to_csv(OUT + "orders.csv", index=False)
order_items.to_csv(OUT + "order_items.csv", index=False)
refunds.to_csv(OUT + "order_item_refunds.csv", index=False)

# Excel: product catalog
products.to_excel(OUT + "products.xlsx", index=False)

# JSON: web analytics
sessions["created_at"] = pd.to_datetime(sessions["created_at"])
pageviews["created_at"] = pd.to_datetime(pageviews["created_at"])
sessions.to_json(OUT + "website_sessions.json", orient="records", date_format="iso")
pageviews.to_json(OUT + "website_pageviews.json", orient="records", date_format="iso")

print("source files written to", OUT)
