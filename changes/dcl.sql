-- ============================================================
--  DCL — Run this in pgAdmin Query Tool (cafe_db selected)
--  Creates real PostgreSQL login users with specific permissions.
--  Flask connects AS these users — GRANT/REVOKE takes effect immediately.
-- ============================================================

-- STEP 1: Create the 3 login roles
DROP ROLE IF EXISTS cafe_barista;
DROP ROLE IF EXISTS cafe_cashier;
DROP ROLE IF EXISTS cafe_manager;

CREATE ROLE cafe_barista  LOGIN PASSWORD 'barista123';
CREATE ROLE cafe_cashier  LOGIN PASSWORD 'cashier123';
CREATE ROLE cafe_manager  LOGIN PASSWORD 'manager123';

-- STEP 2: Schema access (required for all)
GRANT USAGE ON SCHEMA public TO cafe_barista, cafe_cashier, cafe_manager;

-- STEP 3: BARISTA — view menu and orders, update order status only
GRANT SELECT           ON menu_item, orders, order_item, customer TO cafe_barista;
GRANT UPDATE (order_status) ON orders TO cafe_barista;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cafe_barista;

-- STEP 4: CASHIER — barista access + manage customers and bills
GRANT SELECT           ON menu_item, orders, order_item TO cafe_cashier;
GRANT UPDATE (order_status) ON orders TO cafe_cashier;
GRANT SELECT, INSERT, UPDATE ON customer TO cafe_cashier;
GRANT SELECT, INSERT, UPDATE ON bill     TO cafe_cashier;
GRANT SELECT, DELETE   ON valid_promo_code TO cafe_cashier;
GRANT SELECT           ON audit_log TO cafe_cashier;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cafe_cashier;

-- STEP 5: MANAGER — full access, cannot delete audit_log
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA public TO cafe_manager;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO cafe_manager;
REVOKE DELETE ON audit_log FROM cafe_manager;

-- STEP 6: Views access
GRANT SELECT ON vw_order_summary, vw_revenue_report, vw_popular_items TO cafe_manager;
GRANT SELECT ON vw_order_summary TO cafe_cashier;

-- ── VIVA DEMO COMMANDS ─────────────────────────────────────────
-- Run one of these live, then test in the app — DB rejects it instantly.

-- Demo: Remove cashier's ability to add new customers
-- REVOKE INSERT ON customer FROM cafe_cashier;
-- Restore:
-- GRANT INSERT ON customer TO cafe_cashier;

-- Demo: Remove barista from seeing orders
-- REVOKE SELECT ON orders FROM cafe_barista;
-- Restore:
-- GRANT SELECT ON orders TO cafe_barista;

-- Demo: Remove manager from deleting menu items
-- REVOKE DELETE ON menu_item FROM cafe_manager;
-- Restore:
-- GRANT DELETE ON menu_item TO cafe_manager;

-- ── VERIFY what each role can do ──────────────────────────────
-- SELECT grantee, table_name, privilege_type
-- FROM information_schema.role_table_grants
-- WHERE grantee IN ('cafe_barista','cafe_cashier','cafe_manager')
-- ORDER BY grantee, table_name;
