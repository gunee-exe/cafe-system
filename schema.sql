-- ============================================================
--  CAFE DATABASE — schema.sql
--  Run this file in psql:  \i schema.sql
-- ============================================================

-- Drop tables if re-running
DROP TABLE IF EXISTS audit_log      CASCADE;
DROP TABLE IF EXISTS bill           CASCADE;
DROP TABLE IF EXISTS order_item     CASCADE;
DROP TABLE IF EXISTS orders         CASCADE;
DROP TABLE IF EXISTS valid_promo_code CASCADE;
DROP TABLE IF EXISTS menu_item      CASCADE;
DROP TABLE IF EXISTS employee       CASCADE;
DROP TABLE IF EXISTS customer       CASCADE;

-- ─────────────────────────────────────────
--  TABLES (DDL)
-- ─────────────────────────────────────────

CREATE TABLE customer (
    customer_id  SERIAL       PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    contact      VARCHAR(20)  NOT NULL UNIQUE,
    membership   VARCHAR(10)  NOT NULL DEFAULT 'Regular'
                              CHECK (membership IN ('Regular','Member','VIP')),
    loyalty_pts  INT          NOT NULL DEFAULT 0 CHECK (loyalty_pts >= 0)
);

CREATE TABLE employee (
    employee_id  SERIAL       PRIMARY KEY,
    emp_name     VARCHAR(100) NOT NULL,
    dob          DATE         NOT NULL,
    role         VARCHAR(20)  NOT NULL CHECK (role IN ('Barista','Cashier','Manager')),
    salary       NUMERIC(10,2) NOT NULL CHECK (salary > 0)
);

CREATE TABLE menu_item (
    item_id      SERIAL       PRIMARY KEY,
    item_name    VARCHAR(100) NOT NULL UNIQUE,
    price        NUMERIC(8,2) NOT NULL CHECK (price > 0),
    category     VARCHAR(20)  NOT NULL CHECK (category IN ('Hot Drink','Cold Drink','Food Item')),
    is_available BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE valid_promo_code (
    code           VARCHAR(30)   PRIMARY KEY,
    discount_type  VARCHAR(10)   NOT NULL CHECK (discount_type IN ('percent','fixed')),
    discount_amount NUMERIC(8,2) NOT NULL CHECK (discount_amount > 0),
    expiry_date    DATE          NOT NULL,
    min_order_val  NUMERIC(8,2) NOT NULL DEFAULT 0
);

CREATE TABLE orders (
    order_id       SERIAL      PRIMARY KEY,
    customer_id    INT         NOT NULL REFERENCES customer(customer_id) ON DELETE CASCADE,
    order_status   VARCHAR(20) NOT NULL DEFAULT 'Pending'
                               CHECK (order_status IN ('Pending','Preparing','Ready','Completed','Cancelled')),
    order_datetime TIMESTAMP   NOT NULL DEFAULT NOW(),
    order_type     VARCHAR(15) NOT NULL CHECK (order_type IN ('Dine-In','Takeaway','Delivery'))
);

CREATE TABLE order_item (
    order_id   INT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    item_id    INT NOT NULL REFERENCES menu_item(item_id) ON DELETE RESTRICT,
    quantity   INT NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (order_id, item_id)
);

CREATE TABLE bill (
    bill_id         SERIAL       PRIMARY KEY,
    order_id        INT          NOT NULL UNIQUE REFERENCES orders(order_id) ON DELETE CASCADE,
    total_amount    NUMERIC(10,2) NOT NULL,
    discount_applied NUMERIC(10,2) NOT NULL DEFAULT 0,
    final_amount    NUMERIC(10,2) NOT NULL,   -- derived, stored for performance
    payment_mode    VARCHAR(20)  NOT NULL CHECK (payment_mode IN ('Cash','Card','JazzCash','EasyPaisa')),
    payment_status  VARCHAR(10)  NOT NULL DEFAULT 'Unpaid' CHECK (payment_status IN ('Paid','Unpaid')),
    promo_code_used VARCHAR(30)  DEFAULT NULL
);

CREATE TABLE audit_log (
    audit_id         SERIAL       PRIMARY KEY,
    action_type      VARCHAR(10)  NOT NULL,   -- INSERT / UPDATE / DELETE
    table_name       VARCHAR(50)  NOT NULL,
    record_id        VARCHAR(50),
    changed_by       VARCHAR(100) DEFAULT current_user,
    change_timestamp TIMESTAMP    DEFAULT NOW(),
    old_value        TEXT,
    new_value        TEXT
);

-- ─────────────────────────────────────────
--  INDEXES
-- ─────────────────────────────────────────
CREATE INDEX idx_orders_customer    ON orders(customer_id);
CREATE INDEX idx_orders_status      ON orders(order_status);
CREATE INDEX idx_order_item_order   ON order_item(order_id);
CREATE INDEX idx_bill_order         ON bill(order_id);
CREATE INDEX idx_bill_payment_status ON bill(payment_status);
CREATE INDEX idx_menu_category      ON menu_item(category);
CREATE INDEX idx_promo_expiry       ON valid_promo_code(expiry_date);
CREATE INDEX idx_audit_table        ON audit_log(table_name);

-- ─────────────────────────────────────────
--  VIEWS
-- ─────────────────────────────────────────

-- Full order summary view
CREATE OR REPLACE VIEW vw_order_summary AS
SELECT
    o.order_id,
    c.name         AS customer_name,
    c.membership,
    o.order_type,
    o.order_status,
    o.order_datetime,
    COUNT(oi.item_id)       AS item_count,
    SUM(oi.quantity)        AS total_qty,
    SUM(oi.quantity * m.price) AS order_total
FROM orders o
JOIN customer   c  ON o.customer_id = c.customer_id
JOIN order_item oi ON o.order_id    = oi.order_id
JOIN menu_item  m  ON oi.item_id    = m.item_id
GROUP BY o.order_id, c.name, c.membership, o.order_type, o.order_status, o.order_datetime;

-- Revenue report view
CREATE OR REPLACE VIEW vw_revenue_report AS
SELECT
    DATE(o.order_datetime) AS order_date,
    COUNT(DISTINCT b.bill_id)       AS bills_count,
    SUM(b.total_amount)             AS gross_revenue,
    SUM(b.discount_applied)         AS total_discounts,
    SUM(b.final_amount)             AS net_revenue,
    SUM(CASE WHEN b.payment_status='Paid' THEN b.final_amount ELSE 0 END) AS collected
FROM bill b
JOIN orders o ON b.order_id = o.order_id
GROUP BY DATE(o.order_datetime)
ORDER BY order_date DESC;

-- Popular items view
CREATE OR REPLACE VIEW vw_popular_items AS
SELECT
    m.item_id,
    m.item_name,
    m.category,
    m.price,
    SUM(oi.quantity) AS total_sold,
    COUNT(DISTINCT oi.order_id) AS order_count
FROM menu_item m
JOIN order_item oi ON m.item_id = oi.item_id
GROUP BY m.item_id, m.item_name, m.category, m.price
ORDER BY total_sold DESC;

-- ─────────────────────────────────────────
--  DCL — USER PERMISSIONS
-- ─────────────────────────────────────────
-- Run these as superuser after creating the roles:
-- CREATE ROLE cafe_staff   LOGIN PASSWORD 'staff123';
-- CREATE ROLE cafe_manager LOGIN PASSWORD 'manager123';
-- CREATE ROLE cafe_readonly LOGIN PASSWORD 'readonly123';

-- Staff: can read/write orders and bills, read menu
-- GRANT SELECT, INSERT, UPDATE ON orders, order_item, bill TO cafe_staff;
-- GRANT SELECT ON menu_item, customer, valid_promo_code TO cafe_staff;
-- GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cafe_staff;

-- Manager: full access except audit_log delete
-- GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO cafe_manager;
-- GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO cafe_manager;
-- REVOKE DELETE ON audit_log FROM cafe_manager;

-- Readonly: for reporting
-- GRANT SELECT ON ALL TABLES IN SCHEMA public TO cafe_readonly;

-- ─────────────────────────────────────────
--  MOCK DATA (15+ records per table)
-- ─────────────────────────────────────────

INSERT INTO customer (name, contact, membership, loyalty_pts) VALUES
('Ali Hassan',       '03001234567', 'Regular', 0),
('Sara Ahmed',       '03012345678', 'Member',  120),
('Usman Khan',       '03023456789', 'VIP',     450),
('Ayesha Siddiqui',  '03034567890', 'Regular', 20),
('Bilal Mahmood',    '03045678901', 'Member',  80),
('Fatima Malik',     '03056789012', 'VIP',     600),
('Omar Farooq',      '03067890123', 'Regular', 0),
('Zainab Ali',       '03078901234', 'Member',  200),
('Hamza Raza',       '03089012345', 'Regular', 10),
('Maryam Iqbal',     '03090123456', 'VIP',     900),
('Tariq Hussain',    '03101234567', 'Regular', 0),
('Nadia Baig',       '03112345678', 'Member',  55),
('Imran Sheikh',     '03123456789', 'Regular', 0),
('Sana Butt',        '03134567890', 'Member',  310),
('Kamran Mirza',     '03145678901', 'VIP',     750);

INSERT INTO employee (emp_name, dob, role, salary) VALUES
('Junaid Alam',      '1995-03-12', 'Barista',  35000),
('Rabia Noor',       '1998-07-25', 'Cashier',  30000),
('Shahid Mehmood',   '1985-11-01', 'Manager',  65000),
('Asma Riaz',        '1997-05-14', 'Barista',  35000),
('Faisal Qureshi',   '1993-09-30', 'Cashier',  30000),
('Hina Zaidi',       '1990-02-18', 'Barista',  37000),
('Naveed Akhtar',    '1988-12-05', 'Manager',  70000),
('Sobia Tahir',      '2000-06-22', 'Cashier',  28000),
('Zubair Hassan',    '1996-08-15', 'Barista',  36000),
('Aroha Malik',      '1999-04-10', 'Cashier',  29000),
('Danish Khan',      '1994-01-28', 'Barista',  35500),
('Uzma Farhat',      '1991-10-07', 'Manager',  68000),
('Rizwan Aslam',     '2001-03-19', 'Cashier',  27000),
('Maira Chaudhry',   '1997-11-11', 'Barista',  34000),
('Khalid Javed',     '1986-07-03', 'Manager',  72000);

INSERT INTO menu_item (item_name, price, category, is_available) VALUES
('Espresso',          180, 'Hot Drink',  TRUE),
('Cappuccino',        250, 'Hot Drink',  TRUE),
('Latte',             270, 'Hot Drink',  TRUE),
('Americano',         200, 'Hot Drink',  TRUE),
('Hot Chocolate',     280, 'Hot Drink',  TRUE),
('Cold Brew',         300, 'Cold Drink', TRUE),
('Iced Latte',        290, 'Cold Drink', TRUE),
('Frappuccino',       350, 'Cold Drink', TRUE),
('Iced Americano',    220, 'Cold Drink', TRUE),
('Mango Smoothie',    320, 'Cold Drink', TRUE),
('Croissant',         180, 'Food Item',  TRUE),
('Club Sandwich',     350, 'Food Item',  TRUE),
('Chicken Wrap',      400, 'Food Item',  TRUE),
('Brownie',           200, 'Food Item',  TRUE),
('Cheesecake Slice',  280, 'Food Item',  TRUE),
('Blueberry Muffin',  150, 'Food Item',  TRUE),
('Matcha Latte',      310, 'Hot Drink',  FALSE);

INSERT INTO valid_promo_code (code, discount_type, discount_amount, expiry_date, min_order_val) VALUES
('WELCOME10',  'percent', 10,  '2025-12-31', 0),
('FLAT50',     'fixed',   50,  '2025-09-30', 300),
('VIP20',      'percent', 20,  '2025-12-31', 500),
('SUMMER15',   'percent', 15,  '2025-08-31', 400),
('NEWUSER',    'fixed',   100, '2025-12-31', 200),
('LUNCH25',    'percent', 25,  '2025-07-31', 600),
('KARACHI5',   'percent', 5,   '2025-12-31', 0),
('HOLIDAY30',  'percent', 30,  '2025-12-25', 800),
('COFFEE10',   'fixed',   10,  '2025-10-31', 150),
('MEGA200',    'fixed',   200, '2025-11-30', 1000);

-- Insert sample orders and bills (abbreviated — triggers will log these)
INSERT INTO orders (customer_id, order_status, order_datetime, order_type) VALUES
(1,  'Completed', NOW() - INTERVAL '5 days',  'Dine-In'),
(2,  'Completed', NOW() - INTERVAL '4 days',  'Takeaway'),
(3,  'Completed', NOW() - INTERVAL '3 days',  'Dine-In'),
(4,  'Pending',   NOW() - INTERVAL '2 hours', 'Delivery'),
(5,  'Completed', NOW() - INTERVAL '2 days',  'Dine-In'),
(6,  'Preparing', NOW() - INTERVAL '1 hour',  'Takeaway'),
(7,  'Completed', NOW() - INTERVAL '6 days',  'Dine-In'),
(8,  'Completed', NOW() - INTERVAL '1 day',   'Delivery'),
(9,  'Ready',     NOW() - INTERVAL '30 mins', 'Dine-In'),
(10, 'Completed', NOW() - INTERVAL '7 days',  'Takeaway');

INSERT INTO order_item (order_id, item_id, quantity) VALUES
(1, 1, 2),(1, 11, 1),
(2, 6, 1),(2, 12, 1),
(3, 3, 2),(3, 15, 2),
(4, 2, 1),(4, 13, 1),
(5, 7, 2),(5, 14, 2),
(6, 4, 1),(6, 16, 3),
(7, 5, 1),(7, 11, 2),
(8, 8, 2),(8, 12, 1),
(9, 9, 1),(9, 14, 1),
(10,10, 2),(10,15, 1);

INSERT INTO bill (order_id, total_amount, discount_applied, final_amount, payment_mode, payment_status, promo_code_used) VALUES
(1,  540,  0,   540,  'Cash',      'Paid',   NULL),
(2,  650,  50,  600,  'Card',      'Paid',   'FLAT50'),
(3, 1100,  0,  1100,  'JazzCash',  'Paid',   NULL),
(5, 1180,  0,  1180,  'Cash',      'Paid',   NULL),
(7,  640,  0,   640,  'Card',      'Paid',   NULL),
(8, 1050,  0,  1050,  'EasyPaisa', 'Paid',   NULL),
(10,1200, 120, 1080,  'Cash',      'Paid',   'VIP20');
