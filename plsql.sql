-- ============================================================
--  CAFE DATABASE — plsql.sql
--  All PL/pgSQL: Triggers, Packages (via schemas), Cursors
--  Run AFTER schema.sql:  \i plsql.sql
-- ============================================================

-- ─────────────────────────────────────────
--  1. AUDIT LOG TRIGGER FUNCTION
--     Fires AFTER INSERT/UPDATE/DELETE on
--     customer, orders, bill, menu_item, employee
-- ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_audit_logger()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_record_id  TEXT;
    v_old_val    TEXT := NULL;
    v_new_val    TEXT := NULL;
BEGIN
    -- Determine record ID based on table
    IF TG_TABLE_NAME = 'customer' THEN
        v_record_id := COALESCE(NEW.customer_id::TEXT, OLD.customer_id::TEXT);
    ELSIF TG_TABLE_NAME = 'orders' THEN
        v_record_id := COALESCE(NEW.order_id::TEXT, OLD.order_id::TEXT);
    ELSIF TG_TABLE_NAME = 'bill' THEN
        v_record_id := COALESCE(NEW.bill_id::TEXT, OLD.bill_id::TEXT);
    ELSIF TG_TABLE_NAME = 'menu_item' THEN
        v_record_id := COALESCE(NEW.item_id::TEXT, OLD.item_id::TEXT);
    ELSIF TG_TABLE_NAME = 'employee' THEN
        v_record_id := COALESCE(NEW.employee_id::TEXT, OLD.employee_id::TEXT);
    ELSE
        v_record_id := 'N/A';
    END IF;

    -- Build old/new value strings
    IF TG_OP = 'INSERT' THEN
        v_new_val := row_to_json(NEW)::TEXT;
    ELSIF TG_OP = 'UPDATE' THEN
        v_old_val := row_to_json(OLD)::TEXT;
        v_new_val := row_to_json(NEW)::TEXT;
    ELSIF TG_OP = 'DELETE' THEN
        v_old_val := row_to_json(OLD)::TEXT;
    END IF;

    INSERT INTO audit_log
        (action_type, table_name, record_id, changed_by, change_timestamp, old_value, new_value)
    VALUES
        (TG_OP, TG_TABLE_NAME, v_record_id, current_user, NOW(), v_old_val, v_new_val);

    RETURN COALESCE(NEW, OLD);
END;
$$;

-- Attach audit trigger to all key tables
DROP TRIGGER IF EXISTS trg_audit_customer  ON customer;
DROP TRIGGER IF EXISTS trg_audit_orders    ON orders;
DROP TRIGGER IF EXISTS trg_audit_bill      ON bill;
DROP TRIGGER IF EXISTS trg_audit_menu_item ON menu_item;
DROP TRIGGER IF EXISTS trg_audit_employee  ON employee;

CREATE TRIGGER trg_audit_customer
    AFTER INSERT OR UPDATE OR DELETE ON customer
    FOR EACH ROW EXECUTE FUNCTION fn_audit_logger();

CREATE TRIGGER trg_audit_orders
    AFTER INSERT OR UPDATE OR DELETE ON orders
    FOR EACH ROW EXECUTE FUNCTION fn_audit_logger();

CREATE TRIGGER trg_audit_bill
    AFTER INSERT OR UPDATE OR DELETE ON bill
    FOR EACH ROW EXECUTE FUNCTION fn_audit_logger();

CREATE TRIGGER trg_audit_menu_item
    AFTER INSERT OR UPDATE OR DELETE ON menu_item
    FOR EACH ROW EXECUTE FUNCTION fn_audit_logger();

CREATE TRIGGER trg_audit_employee
    AFTER INSERT OR UPDATE OR DELETE ON employee
    FOR EACH ROW EXECUTE FUNCTION fn_audit_logger();


-- ─────────────────────────────────────────
--  2. LOYALTY POINTS TRIGGER
--     AFTER a bill is inserted and marked Paid,
--     award loyalty points to customer
--     Rule: 1 point per Rs.10 spent
-- ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_award_loyalty_points()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_customer_id  INT;
    v_points_earned INT;
BEGIN
    -- Award points only when payment_status transitions to 'Paid'
    -- On INSERT: only if inserted as Paid
    -- On UPDATE: only if it changed from Unpaid -> Paid (prevents double-award)
    IF NEW.payment_status = 'Paid' AND
       (TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND OLD.payment_status <> 'Paid')) THEN

        SELECT o.customer_id INTO v_customer_id
        FROM orders o WHERE o.order_id = NEW.order_id;

        v_points_earned := FLOOR(NEW.final_amount / 10);

        UPDATE customer
        SET loyalty_pts = loyalty_pts + v_points_earned
        WHERE customer_id = v_customer_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_loyalty_points ON bill;
CREATE TRIGGER trg_loyalty_points
    AFTER INSERT OR UPDATE ON bill
    FOR EACH ROW EXECUTE FUNCTION fn_award_loyalty_points();


-- ─────────────────────────────────────────
--  3. PREVENT DUPLICATE ACTIVE ORDER TRIGGER
--     A customer cannot have more than one
--     Pending/Preparing order at a time
-- ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_check_duplicate_order()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_active_count INT;
BEGIN
    SELECT COUNT(*) INTO v_active_count
    FROM orders
    WHERE customer_id = NEW.customer_id
      AND order_status IN ('Pending', 'Preparing')
      AND order_id <> COALESCE(NEW.order_id, -1);

    IF v_active_count > 0 THEN
        RAISE EXCEPTION 'Customer already has an active order in progress.';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_check_duplicate_order ON orders;
CREATE TRIGGER trg_check_duplicate_order
    BEFORE INSERT ON orders
    FOR EACH ROW EXECUTE FUNCTION fn_check_duplicate_order();


-- ─────────────────────────────────────────
--  4. AUTO UPGRADE MEMBERSHIP TRIGGER
--     When loyalty_pts hits 500 → upgrade to VIP
--     When loyalty_pts hits 100 → upgrade to Member
-- ─────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_auto_upgrade_membership()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.loyalty_pts >= 500 AND NEW.membership <> 'VIP' THEN
        NEW.membership := 'VIP';
        RAISE NOTICE 'Customer % upgraded to VIP!', NEW.customer_id;
    ELSIF NEW.loyalty_pts >= 100 AND NEW.membership = 'Regular' THEN
        NEW.membership := 'Member';
        RAISE NOTICE 'Customer % upgraded to Member!', NEW.customer_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_upgrade_membership ON customer;
CREATE TRIGGER trg_auto_upgrade_membership
    BEFORE UPDATE OF loyalty_pts ON customer
    FOR EACH ROW EXECUTE FUNCTION fn_auto_upgrade_membership();


-- ─────────────────────────────────────────
--  5. PACKAGES
--     PostgreSQL uses schemas + functions to
--     simulate Oracle-style packages
-- ─────────────────────────────────────────

DROP SCHEMA IF EXISTS pkg_billing  CASCADE;
DROP SCHEMA IF EXISTS pkg_reports  CASCADE;
DROP SCHEMA IF EXISTS pkg_inventory CASCADE;

CREATE SCHEMA pkg_billing;
CREATE SCHEMA pkg_reports;
CREATE SCHEMA pkg_inventory;


-- ── PACKAGE: pkg_billing ─────────────────
-- Business logic for bill calculation and payment

CREATE OR REPLACE FUNCTION pkg_billing.calculate_order_total(p_order_id INT)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE
    v_total NUMERIC := 0;
BEGIN
    SELECT SUM(oi.quantity * m.price)
    INTO v_total
    FROM order_item oi
    JOIN menu_item m ON oi.item_id = m.item_id
    WHERE oi.order_id = p_order_id;

    RETURN COALESCE(v_total, 0);
END;
$$;

CREATE OR REPLACE FUNCTION pkg_billing.apply_promo(
    p_total      NUMERIC,
    p_code       VARCHAR,
    OUT v_discount  NUMERIC,
    OUT v_final     NUMERIC,
    OUT v_message   TEXT
) LANGUAGE plpgsql AS $$
DECLARE
    rec valid_promo_code%ROWTYPE;
BEGIN
    v_discount := 0;
    v_final    := p_total;
    v_message  := 'No promo code applied.';

    IF p_code IS NULL OR p_code = '' THEN
        RETURN;
    END IF;

    SELECT * INTO rec
    FROM valid_promo_code
    WHERE code = p_code
      AND expiry_date >= CURRENT_DATE
      AND p_total >= min_order_val;

    IF NOT FOUND THEN
        v_message := 'Promo code invalid, expired, or order total too low.';
        RETURN;
    END IF;

    IF rec.discount_type = 'percent' THEN
        v_discount := ROUND(p_total * rec.discount_amount / 100, 2);
    ELSE
        v_discount := rec.discount_amount;
    END IF;

    v_final   := GREATEST(p_total - v_discount, 0);
    v_message := 'Promo applied: ' || p_code || '. Saved Rs.' || v_discount;
END;
$$;

CREATE OR REPLACE FUNCTION pkg_billing.mark_bill_paid(p_bill_id INT)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    v_status TEXT;
BEGIN
    SELECT payment_status INTO v_status
    FROM bill WHERE bill_id = p_bill_id;

    IF NOT FOUND THEN
        RETURN 'Bill not found.';
    END IF;
    IF v_status = 'Paid' THEN
        RETURN 'Bill already paid.';
    END IF;

    UPDATE bill SET payment_status = 'Paid' WHERE bill_id = p_bill_id;
    RETURN 'Bill #' || p_bill_id || ' marked as Paid.';
END;
$$;


-- ── PACKAGE: pkg_reports ─────────────────
-- Business reporting functions

CREATE OR REPLACE FUNCTION pkg_reports.daily_revenue(p_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE(
    total_bills    BIGINT,
    gross_revenue  NUMERIC,
    total_discount NUMERIC,
    net_revenue    NUMERIC
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(b.bill_id),
        SUM(b.total_amount),
        SUM(b.discount_applied),
        SUM(b.final_amount)
    FROM bill b
    JOIN orders o ON b.order_id = o.order_id
    WHERE DATE(o.order_datetime) = p_date;
END;
$$;

CREATE OR REPLACE FUNCTION pkg_reports.top_customers(p_limit INT DEFAULT 5)
RETURNS TABLE(
    customer_id   INT,
    customer_name VARCHAR,
    membership    VARCHAR,
    total_spent   NUMERIC,
    order_count   BIGINT
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        c.customer_id,
        c.name,
        c.membership,
        SUM(b.final_amount),
        COUNT(DISTINCT o.order_id)
    FROM customer c
    JOIN orders o ON c.customer_id = o.customer_id
    JOIN bill b   ON o.order_id    = b.order_id
    WHERE b.payment_status = 'Paid'
    GROUP BY c.customer_id, c.name, c.membership
    ORDER BY SUM(b.final_amount) DESC
    LIMIT p_limit;
END;
$$;

CREATE OR REPLACE FUNCTION pkg_reports.monthly_summary(
    p_year  INT DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::INT,
    p_month INT DEFAULT EXTRACT(MONTH FROM CURRENT_DATE)::INT
)
RETURNS TABLE(
    order_date    DATE,
    orders_placed BIGINT,
    revenue       NUMERIC
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        DATE(o.order_datetime),
        COUNT(DISTINCT o.order_id),
        SUM(b.final_amount)
    FROM orders o
    JOIN bill b ON o.order_id = b.order_id
    WHERE EXTRACT(YEAR  FROM o.order_datetime) = p_year
      AND EXTRACT(MONTH FROM o.order_datetime) = p_month
    GROUP BY DATE(o.order_datetime)
    ORDER BY DATE(o.order_datetime);
END;
$$;


-- ── PACKAGE: pkg_inventory ───────────────
-- Menu item availability management

CREATE OR REPLACE FUNCTION pkg_inventory.toggle_availability(p_item_id INT)
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE
    v_current BOOLEAN;
    v_name    VARCHAR;
BEGIN
    SELECT is_available, item_name INTO v_current, v_name
    FROM menu_item WHERE item_id = p_item_id;

    IF NOT FOUND THEN
        RETURN 'Item not found.';
    END IF;

    UPDATE menu_item SET is_available = NOT v_current WHERE item_id = p_item_id;
    RETURN v_name || ' is now ' || CASE WHEN NOT v_current THEN 'AVAILABLE' ELSE 'UNAVAILABLE' END;
END;
$$;

CREATE OR REPLACE FUNCTION pkg_inventory.items_by_category(p_category VARCHAR)
RETURNS TABLE(
    item_id      INT,
    item_name    VARCHAR,
    price        NUMERIC,
    is_available BOOLEAN
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT m.item_id, m.item_name, m.price, m.is_available
    FROM menu_item m
    WHERE m.category = p_category
    ORDER BY m.item_name;
END;
$$;


-- ─────────────────────────────────────────
--  6. CURSORS (named blocks)
--     These are example PL/pgSQL blocks with
--     explicit cursors — run manually in psql
--     or call as needed
-- ─────────────────────────────────────────

-- Cursor Block 1: Print all unpaid bills with customer name
DO $$
DECLARE
    cur_unpaid CURSOR FOR
        SELECT b.bill_id, c.name, b.final_amount, b.payment_mode
        FROM bill b
        JOIN orders o ON b.order_id   = o.order_id
        JOIN customer c ON o.customer_id = c.customer_id
        WHERE b.payment_status = 'Unpaid'
        ORDER BY b.bill_id;

    rec RECORD;
    v_count INT := 0;
BEGIN
    OPEN cur_unpaid;
    LOOP
        FETCH cur_unpaid INTO rec;
        EXIT WHEN NOT FOUND;
        v_count := v_count + 1;
        RAISE NOTICE 'Bill #%: % owes Rs.% (via %)',
            rec.bill_id, rec.name, rec.final_amount, rec.payment_mode;
    END LOOP;
    CLOSE cur_unpaid;
    RAISE NOTICE 'Total unpaid bills: %', v_count;
END;
$$;


-- Cursor Block 2: Award bonus loyalty points to VIP customers
-- (Business logic: VIP customers get 2x loyalty points)
DO $$
DECLARE
    cur_vip CURSOR FOR
        SELECT customer_id, name, loyalty_pts
        FROM customer WHERE membership = 'VIP';

    rec        RECORD;
    v_bonus    INT;
    v_updated  INT := 0;
BEGIN
    OPEN cur_vip;
    LOOP
        FETCH cur_vip INTO rec;
        EXIT WHEN NOT FOUND;

        v_bonus := 50; -- flat 50 bonus points for VIPs this month
        UPDATE customer
        SET loyalty_pts = loyalty_pts + v_bonus
        WHERE customer_id = rec.customer_id;

        RAISE NOTICE 'VIP bonus: % (ID %) received % bonus pts. New total: %',
            rec.name, rec.customer_id, v_bonus, rec.loyalty_pts + v_bonus;
        v_updated := v_updated + 1;
    END LOOP;
    CLOSE cur_vip;
    RAISE NOTICE '% VIP customers updated.', v_updated;
END;
$$;


-- Cursor Block 3: Generate revenue summary per category
DO $$
DECLARE
    cur_cat CURSOR FOR
        SELECT m.category,
               SUM(oi.quantity * m.price) AS category_revenue,
               SUM(oi.quantity)           AS units_sold
        FROM order_item oi
        JOIN menu_item m ON oi.item_id = m.item_id
        GROUP BY m.category
        ORDER BY category_revenue DESC;

    rec RECORD;
BEGIN
    RAISE NOTICE '=== REVENUE BY CATEGORY ===';
    OPEN cur_cat;
    LOOP
        FETCH cur_cat INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Category: % | Revenue: Rs.% | Units Sold: %',
            rec.category, rec.category_revenue, rec.units_sold;
    END LOOP;
    CLOSE cur_cat;
END;
$$;


-- ─────────────────────────────────────────
--  7. ADVANCED SQL QUERIES
--     (For Phase III of the project)
-- ─────────────────────────────────────────

-- INNER JOIN: Orders with customer and total
SELECT o.order_id, c.name, o.order_type, o.order_status,
       SUM(oi.quantity * m.price) AS order_total
FROM orders o
INNER JOIN customer   c  ON o.customer_id = c.customer_id
INNER JOIN order_item oi ON o.order_id    = oi.order_id
INNER JOIN menu_item  m  ON oi.item_id    = m.item_id
GROUP BY o.order_id, c.name, o.order_type, o.order_status;

-- LEFT JOIN: All customers, even those with no orders
SELECT c.customer_id, c.name, c.membership,
       COUNT(o.order_id) AS total_orders
FROM customer c
LEFT JOIN orders o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.name, c.membership
ORDER BY total_orders DESC;

-- RIGHT JOIN: All menu items and how many times ordered
SELECT m.item_name, m.category,
       COALESCE(SUM(oi.quantity), 0) AS times_ordered
FROM order_item oi
RIGHT JOIN menu_item m ON oi.item_id = m.item_id
GROUP BY m.item_name, m.category
ORDER BY times_ordered DESC;

-- FULL JOIN: Customers and employees by name pattern
SELECT 'Customer' AS type, name FROM customer
FULL OUTER JOIN employee ON customer.name = employee.emp_name
WHERE customer.name IS NOT NULL OR employee.emp_name IS NOT NULL;

-- UNION: List all names (customers + employees)
SELECT name AS person_name, 'Customer' AS role FROM customer
UNION
SELECT emp_name, role FROM employee
ORDER BY role;

-- INTERSECT: Contacts that appear in both tables (edge case demo)
SELECT contact AS detail FROM customer
INTERSECT
SELECT emp_name FROM employee;

-- EXCEPT / MINUS: Customers who have never placed an order
SELECT customer_id, name FROM customer
EXCEPT
SELECT DISTINCT c.customer_id, c.name
FROM customer c JOIN orders o ON c.customer_id = o.customer_id;

-- Non-correlated subquery: Items priced above average
SELECT item_name, price, category
FROM menu_item
WHERE price > (SELECT AVG(price) FROM menu_item)
ORDER BY price DESC;

-- Correlated subquery: Customers who spent above average
SELECT c.name, c.membership,
       (SELECT SUM(b.final_amount)
        FROM orders o JOIN bill b ON o.order_id=b.order_id
        WHERE o.customer_id = c.customer_id) AS total_spent
FROM customer c
WHERE (
    SELECT COALESCE(SUM(b.final_amount),0)
    FROM orders o JOIN bill b ON o.order_id=b.order_id
    WHERE o.customer_id = c.customer_id
) > (
    SELECT AVG(sub.total)
    FROM (
        SELECT SUM(b2.final_amount) AS total
        FROM orders o2 JOIN bill b2 ON o2.order_id=b2.order_id
        GROUP BY o2.customer_id
    ) sub
);