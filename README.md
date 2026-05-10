# ☕ Cafe Manager — DBMS Semester Project

#Deployment Link: cafe-system-production-2ad4.up.railway.app

## Setup Instructions (step by step)

### Step 1 — Install dependencies
```
pip install flask psycopg2-binary
```

### Step 2 — Create the PostgreSQL database
Open pgAdmin or psql and run:
```sql
CREATE DATABASE cafe_db;
```

### Step 3 — Edit the password in app.py
Open app.py and find this section near the top:
```python
DB_CONFIG = {
    'host': 'localhost',
    'database': 'cafe_db',
    'user': 'postgres',
    'password': 'your_password_here',   # <-- change this to your postgres password
    'port': '5432'
}
```

### Step 4 — Run the SQL schema (creates tables + mock data)
In psql:
```
\c cafe_db
\i schema.sql
```
Or in pgAdmin: open schema.sql and click Run.

### Step 5 — Run the PL/SQL file (triggers, packages, cursors)
```
\i plsql.sql
```

### Step 6 — Run the Flask app
```
python app.py
```
Then open: http://127.0.0.1:5000

---

## Project Files
| File | Description |
|---|---|
| app.py | Flask application — all routes and logic |
| schema.sql | DDL (tables), DCL (permissions), indexes, views, mock data |
| plsql.sql | Triggers, packages (schemas), cursors, advanced SQL queries |
| templates/ | All HTML templates |
| requirements.txt | Python dependencies |

## What the PL/SQL covers (for your report)
- **Triggers**: audit logger, loyalty points award, duplicate order prevention, auto membership upgrade
- **Packages**: pkg_billing (calculate total, apply promo, mark paid), pkg_reports (daily revenue, top customers, monthly summary), pkg_inventory (toggle availability, items by category)
- **Cursors**: unpaid bills cursor, VIP bonus points cursor, revenue by category cursor
- **Views**: vw_order_summary, vw_revenue_report, vw_popular_items
- **Advanced SQL**: INNER/LEFT/RIGHT/FULL JOINs, UNION, INTERSECT, EXCEPT, correlated and non-correlated subqueries
- **Indexing**: on customer_id, order_status, payment_status, category, expiry_date
