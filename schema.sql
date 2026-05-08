-- ============================================================
--  CAFE DATABASE — schema_fixed.sql
--  Fixed to use contact as PK on customer (matches app.py)
-- ============================================================

DROP TABLE IF EXISTS audit_log        CASCADE;
DROP TABLE IF EXISTS bill             CASCADE;
DROP TABLE IF EXISTS order_item       CASCADE;
DROP TABLE IF EXISTS orders           CASCADE;
DROP TABLE IF EXISTS valid_promo_code CASCADE;
DROP TABLE IF EXISTS menu_item        CASCADE;
DROP TABLE IF EXISTS employee         CASCADE;
DROP TABLE IF EXISTS customer         CASCADE;

-- ─────────────────────────────────────────
--  TABLES
-- ─────────────────────────────────────────

CREATE TABLE customer (
    contact      VARCHAR(20)  PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    membership   VARCHAR(10)  NOT NULL DEFAULT 'Regular'
                              CHECK (membership IN ('Regular','Member','VIP')),
    loyalty_pts  INT          NOT NULL DEFAULT 0 CHECK (loyalty_pts >= 0)
);

CREATE TABLE employee (
    employee_id  SERIAL        PRIMARY KEY,
    emp_name     VARCHAR(100)  NOT NULL,
    dob          DATE          NOT NULL,
    role         VARCHAR(20)   NOT NULL CHECK (role IN ('Barista','Cashier','Manager')),
    salary       NUMERIC(10,2) NOT NULL CHECK (salary > 0),
    password     VARCHAR(100)  NOT NULL DEFAULT 'pass123'
);

CREATE TABLE menu_item (
    item_id      SERIAL       PRIMARY KEY,
    item_name    VARCHAR(100) NOT NULL UNIQUE,
    price        NUMERIC(8,2) NOT NULL CHECK (price > 0),
    category     VARCHAR(20)  NOT NULL CHECK (category IN ('Hot Drink','Cold Drink','Food Item')),
    is_available BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE valid_promo_code (
    code            VARCHAR(30)  PRIMARY KEY,
    discount_type   VARCHAR(10)  NOT NULL CHECK (discount_type IN ('percent','fixed')),
    discount_amount NUMERIC(8,2) NOT NULL CHECK (discount_amount > 0),
    expiry_date     DATE         NOT NULL,
    min_order_val   NUMERIC(8,2) NOT NULL DEFAULT 0
);

CREATE TABLE orders (
    order_id          SERIAL      PRIMARY KEY,
    customer_contact  VARCHAR(20) NOT NULL REFERENCES customer(contact) ON DELETE CASCADE,
    order_status      VARCHAR(20) NOT NULL DEFAULT 'Pending'
                                  CHECK (order_status IN ('Pending','Preparing','Ready','Completed','Cancelled')),
    order_datetime    TIMESTAMP   NOT NULL DEFAULT NOW(),
    order_type        VARCHAR(15) NOT NULL CHECK (order_type IN ('Dine-In','Takeaway','Delivery'))
);

CREATE TABLE order_item (
    order_id  INT NOT NULL REFERENCES orders(order_id) ON DELETE CASCADE,
    item_id   INT NOT NULL REFERENCES menu_item(item_id) ON DELETE RESTRICT,
    quantity  INT NOT NULL CHECK (quantity > 0),
    PRIMARY KEY (order_id, item_id)
);

CREATE TABLE bill (
    bill_id          SERIAL        PRIMARY KEY,
    order_id         INT           NOT NULL UNIQUE REFERENCES orders(order_id) ON DELETE CASCADE,
    total_amount     NUMERIC(10,2) NOT NULL,
    discount_applied NUMERIC(10,2) NOT NULL DEFAULT 0,
    final_amount     NUMERIC(10,2) NOT NULL,
    payment_mode     VARCHAR(20)   NOT NULL CHECK (payment_mode IN ('Cash','Card','JazzCash','EasyPaisa')),
    payment_status   VARCHAR(10)   NOT NULL DEFAULT 'Unpaid' CHECK (payment_status IN ('Paid','Unpaid')),
    promo_code_used  VARCHAR(30)   DEFAULT NULL
);

CREATE TABLE audit_log (
    audit_id         SERIAL       PRIMARY KEY,
    action_type      VARCHAR(10)  NOT NULL,
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
CREATE INDEX idx_orders_customer     ON orders(customer_contact);
CREATE INDEX idx_orders_status       ON orders(order_status);
CREATE INDEX idx_order_item_order    ON order_item(order_id);
CREATE INDEX idx_bill_order          ON bill(order_id);
CREATE INDEX idx_bill_payment_status ON bill(payment_status);
CREATE INDEX idx_menu_category       ON menu_item(category);
CREATE INDEX idx_promo_expiry        ON valid_promo_code(expiry_date);
CREATE INDEX idx_audit_table         ON audit_log(table_name);

-- ─────────────────────────────────────────
--  VIEWS
-- ─────────────────────────────────────────

CREATE OR REPLACE VIEW vw_order_summary AS
SELECT
    o.order_id,
    c.name            AS customer_name,
    c.membership,
    o.order_type,
    o.order_status,
    o.order_datetime,
    COUNT(oi.item_id)          AS item_count,
    SUM(oi.quantity)           AS total_qty,
    SUM(oi.quantity * m.price) AS order_total
FROM orders o
JOIN customer   c  ON o.customer_contact = c.contact
JOIN order_item oi ON o.order_id         = oi.order_id
JOIN menu_item  m  ON oi.item_id         = m.item_id
GROUP BY o.order_id, c.name, c.membership, o.order_type, o.order_status, o.order_datetime;

CREATE OR REPLACE VIEW vw_revenue_report AS
SELECT
    DATE(o.order_datetime)                                                    AS order_date,
    COUNT(DISTINCT b.bill_id)                                                 AS bills_count,
    SUM(b.total_amount)                                                       AS gross_revenue,
    SUM(b.discount_applied)                                                   AS total_discounts,
    SUM(b.final_amount)                                                       AS net_revenue,
    SUM(CASE WHEN b.payment_status='Paid' THEN b.final_amount ELSE 0 END)    AS collected
FROM bill b
JOIN orders o ON b.order_id = o.order_id
GROUP BY DATE(o.order_datetime)
ORDER BY order_date DESC;

CREATE OR REPLACE VIEW vw_popular_items AS
SELECT
    m.item_id,
    m.item_name,
    m.category,
    m.price,
    SUM(oi.quantity)            AS total_sold,
    COUNT(DISTINCT oi.order_id) AS order_count
FROM menu_item m
JOIN order_item oi ON m.item_id = oi.item_id
GROUP BY m.item_id, m.item_name, m.category, m.price
ORDER BY total_sold DESC;

-- ─────────────────────────────────────────
--  MOCK DATA
-- ─────────────────────────────────────────

INSERT INTO customer (contact, name, membership, loyalty_pts) VALUES
('03001234567', 'Ali Hassan',      'Regular', 0),
('03012345678', 'Sara Ahmed',      'Member',  120),
('03023456789', 'Usman Khan',      'VIP',     450),
('03034567890', 'Ayesha Siddiqui', 'Regular', 20),
('03045678901', 'Bilal Mahmood',   'Member',  80),
('03056789012', 'Fatima Malik',    'VIP',     600),
('03067890123', 'Omar Farooq',     'Regular', 0),
('03078901234', 'Zainab Ali',      'Member',  200),
('03089012345', 'Hamza Raza',      'Regular', 10),
('03090123456', 'Maryam Iqbal',    'VIP',     900),
('03101234567', 'Tariq Hussain',   'Regular', 0),
('03112345678', 'Nadia Baig',      'Member',  55),
('03123456789', 'Imran Sheikh',    'Regular', 0),
('03134567890', 'Sana Butt',       'Member',  310),
('03145678901', 'Kamran Mirza',    'VIP',     750);

INSERT INTO employee (emp_name, dob, role, salary, password) VALUES
('Junaid Alam',    '1995-03-12', 'Barista', 35000, 'barista123'),
('Rabia Noor',     '1998-07-25', 'Cashier', 30000, 'cashier123'),
('Shahid Mehmood', '1985-11-01', 'Manager', 65000, 'manager123'),
('Asma Riaz',      '1997-05-14', 'Barista', 35000, 'barista123'),
('Faisal Qureshi', '1993-09-30', 'Cashier', 30000, 'cashier123'),
('Hina Zaidi',     '1990-02-18', 'Barista', 37000, 'barista123'),
('Naveed Akhtar',  '1988-12-05', 'Manager', 70000, 'manager123'),
('Sobia Tahir',    '2000-06-22', 'Cashier', 28000, 'cashier123'),
('Zubair Hassan',  '1996-08-15', 'Barista', 36000, 'barista123'),
('Aroha Malik',    '1999-04-10', 'Cashier', 29000, 'cashier123'),
('Danish Khan',    '1994-01-28', 'Barista', 35500, 'barista123'),
('Uzma Farhat',    '1991-10-07', 'Manager', 68000, 'manager123'),
('Rizwan Aslam',   '2001-03-19', 'Cashier', 27000, 'cashier123'),
('Maira Chaudhry', '1997-11-11', 'Barista', 34000, 'barista123'),
('Khalid Javed',   '1986-07-03', 'Manager', 72000, 'manager123');

INSERT INTO menu_item (item_name, price, category, is_available) VALUES
('Espresso',         180, 'Hot Drink',  TRUE),
('Cappuccino',       250, 'Hot Drink',  TRUE),
('Latte',            270, 'Hot Drink',  TRUE),
('Americano',        200, 'Hot Drink',  TRUE),
('Hot Chocolate',    280, 'Hot Drink',  TRUE),
('Cold Brew',        300, 'Cold Drink', TRUE),
('Iced Latte',       290, 'Cold Drink', TRUE),
('Frappuccino',      350, 'Cold Drink', TRUE),
('Iced Americano',   220, 'Cold Drink', TRUE),
('Mango Smoothie',   320, 'Cold Drink', TRUE),
('Croissant',        180, 'Food Item',  TRUE),
('Club Sandwich',    350, 'Food Item',  TRUE),
('Chicken Wrap',     400, 'Food Item',  TRUE),
('Brownie',          200, 'Food Item',  TRUE),
('Cheesecake Slice', 280, 'Food Item',  TRUE),
('Blueberry Muffin', 150, 'Food Item',  TRUE),
('Matcha Latte',     310, 'Hot Drink',  FALSE);

INSERT INTO valid_promo_code (code, discount_type, discount_amount, expiry_date, min_order_val) VALUES
('WELCOME10', 'percent', 10,  '2026-12-31', 0),
('FLAT50',    'fixed',   50,  '2026-09-30', 300),
('VIP20',     'percent', 20,  '2026-12-31', 500),
('SUMMER15',  'percent', 15,  '2026-08-31', 400),
('NEWUSER',   'fixed',   100, '2026-12-31', 200),
('LUNCH25',   'percent', 25,  '2026-07-31', 600),
('KARACHI5',  'percent', 5,   '2026-12-31', 0),
('HOLIDAY30', 'percent', 30,  '2026-12-25', 800),
('COFFEE10',  'fixed',   10,  '2026-10-31', 150),
('MEGA200',   'fixed',   200, '2026-11-30', 1000);

INSERT INTO orders (customer_contact, order_status, order_datetime, order_type) VALUES
('03001234567', 'Completed', NOW() - INTERVAL '5 days',  'Dine-In'),
('03012345678', 'Completed', NOW() - INTERVAL '4 days',  'Takeaway'),
('03023456789', 'Completed', NOW() - INTERVAL '3 days',  'Dine-In'),
('03045678901', 'Completed', NOW() - INTERVAL '2 days',  'Dine-In'),
('03056789012', 'Completed', NOW() - INTERVAL '6 days',  'Dine-In'),
('03067890123', 'Completed', NOW() - INTERVAL '1 day',   'Delivery'),
('03078901234', 'Completed', NOW() - INTERVAL '7 days',  'Takeaway'),
('03089012345', 'Completed', NOW() - INTERVAL '8 days',  'Dine-In'),
('03090123456', 'Completed', NOW() - INTERVAL '9 days',  'Takeaway'),
('03101234567', 'Completed', NOW() - INTERVAL '10 days', 'Dine-In');

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
(1,  540,  0,   540,  'Cash',      'Paid', NULL),
(2,  650,  50,  600,  'Card',      'Paid', 'FLAT50'),
(3, 1100,  0,  1100,  'JazzCash',  'Paid', NULL),
(4, 1180,  0,  1180,  'Cash',      'Paid', NULL),
(5,  640,  0,   640,  'Card',      'Paid', NULL),
(6, 1050,  0,  1050,  'EasyPaisa', 'Paid', NULL),
(7, 1200, 120, 1080,  'Cash',      'Paid', 'VIP20');

-- ─────────────────────────────────────────
--  GRANTS
-- ─────────────────────────────────────────
-- Run these after creating users:
-- CREATE USER cafe_barista WITH PASSWORD 'barista123';
-- CREATE USER cafe_cashier WITH PASSWORD 'cashier123';
-- CREATE USER cafe_manager WITH PASSWORD 'manager123';
-- GRANT CONNECT ON DATABASE railway TO cafe_barista, cafe_cashier, cafe_manager;

GRANT SELECT ON customer, orders, order_item, menu_item TO cafe_barista;
GRANT INSERT, UPDATE ON orders TO cafe_barista;
GRANT INSERT ON order_item TO cafe_barista;

GRANT SELECT ON customer, orders, order_item, menu_item, bill, employee, valid_promo_code TO cafe_cashier;
GRANT INSERT, UPDATE ON orders TO cafe_cashier;
GRANT INSERT ON order_item TO cafe_cashier;
GRANT INSERT, UPDATE ON bill TO cafe_cashier;
GRANT DELETE ON valid_promo_code TO cafe_cashier;

GRANT ALL ON customer TO cafe_manager;
GRANT ALL ON orders TO cafe_manager;
GRANT ALL ON order_item TO cafe_manager;
GRANT ALL ON menu_item TO cafe_manager;
GRANT ALL ON bill TO cafe_manager;
GRANT ALL ON employee TO cafe_manager;
GRANT ALL ON valid_promo_code TO cafe_manager;
GRANT ALL ON audit_log TO cafe_manager;

GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cafe_barista;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cafe_cashier;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cafe_manager;

CREATE USER cafe_barista WITH PASSWORD 'barista123';
CREATE USER cafe_cashier WITH PASSWORD 'cashier123';
CREATE USER cafe_manager WITH PASSWORD 'manager123';
GRANT CONNECT ON DATABASE railway TO cafe_barista, cafe_cashier, cafe_manager;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cafe_barista;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cafe_cashier;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO cafe_manager;

GRANT INSERT ON audit_log TO cafe_barista;
GRANT INSERT ON audit_log TO cafe_cashier;
GRANT USAGE, SELECT ON SEQUENCE audit_log_audit_id_seq TO cafe_barista;
GRANT USAGE, SELECT ON SEQUENCE audit_log_audit_id_seq TO cafe_cashier;

GRANT INSERT ON customer TO cafe_cashier;
GRANT INSERT ON customer TO cafe_barista;
GRANT USAGE, SELECT ON SEQUENCE orders_order_id_seq TO cafe_barista;
GRANT USAGE, SELECT ON SEQUENCE orders_order_id_seq TO cafe_cashier;