# Fuzzy Factory Data Warehouse

This is a group project for IT3101, Data Warehousing and Business Intelligence, at SLIIT. We built an end to end data warehouse and BI solution for a fictional online toy store, Maven Fuzzy Factory, using its real website session, order and product data.

## What this project does

We took the store's operational data, which comes from three different file formats, and turned it into a proper star schema in SQL Server. From there we built a marketing performance data mart and a set of Power BI dashboards on top of it.

The business question behind it is simple. The store wants to know which marketing channels actually bring paying customers, how many website visits turn into orders, and which products do well or get refunded a lot. The raw data on its own cannot answer that, since it sits in six separate tables. The warehouse is what makes that question answerable.

## Dataset

The data is the Maven Fuzzy Factory dataset from Maven Analytics, also available on Kaggle. It covers about three years, from March 2012 to March 2015, and includes close to half a million website sessions and over a million page views.

We split the original six CSV files into three source formats to match the assignment's requirement for multiple data source types.

| Format | Files                                   | Represents                          |
| ------ | --------------------------------------- | ----------------------------------- |
| CSV    | orders, order_items, order_item_refunds | the store's order processing system |
| Excel  | products                                | a small product catalog             |
| JSON   | website_sessions, website_pageviews     | web analytics tracking data         |

## How the pipeline works

Everything from the staging tables onward is done in T-SQL.

1. `etl/prepare_sources.py` reads the original CSVs and writes them back out as CSV, Excel and JSON. This is just a file format change, nothing in here touches SQL Server or does any cleaning that matters for grading.
2. `sql/01_create_staging_tables.sql` creates six staging tables that mirror the source files.
3. `sql/01b_load_staging_from_files.sql` loads those tables straight from the files. The CSVs go in with BULK INSERT. The JSON files go in with OPENROWSET and OPENJSON, since SQL Server has no separate JSON import tool. The four product rows are entered directly.
4. `sql/02_create_warehouse_tables.sql` creates the star schema: three dimension tables and two fact tables.
5. `sql/02b_load_warehouse_from_staging.sql` builds the dimensions and facts from the staging tables with INSERT and SELECT statements. It runs inside one transaction and checks its own row counts before committing, so a partial load cannot happen.
6. `sql/03_create_marketing_data_mart.sql` builds a data mart summarising sessions, orders and revenue by day and by marketing channel.
7. `sql/04_verify_data_mart.sql` is a set of check queries to confirm the mart matches the warehouse totals.

## Project structure

```
dashboards/   PowerBI dashboards
raw_data/     the six original Maven CSVs
sources/      the reshaped CSV, Excel and JSON source files
etl/          prepare_sources.py
sql/          all the SQL scripts, run in the order above
report/       the assignment report and diagrams
```

## Tools used

SQL Server and SQL Server Management Studio for the database and the ETL. Power BI for the dashboards. Python with pandas, only for the source file reshaping step.

## Group

IT3101, Group work. Student details are in the report.

## A note on AI use

Parts of this project, including some of the SQL scripts, the data model design and this documentation, were built with help from an AI assistant. The report has a full section describing exactly how it was used. We ran everything ourselves against our own data and checked the results before including them.
