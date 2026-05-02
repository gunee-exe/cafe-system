from flask import Flask, render_template, request, redirect, url_for, flash, jsonify
import psycopg2
import psycopg2.extras
from datetime import date

app = Flask(__name__)
app.secret_key = 'cafe_secret_key_2024'

# ─── DB CONNECTION ───────────────────────────────────────────────
DB_CONFIG = {
    'host': 'localhost',
    'database': 'cafe_db',
    'user': 'postgres',
    'password': 'mianusman1',   # <-- change this
    'port': '5432'
}

def get_db():
    conn = psycopg2.connect(**DB_CONFIG)
    return conn

# ════════════════════════════════════════
#  HOME
# ════════════════════════════════════════
@app.route('/')
def index():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT COUNT(*) AS c FROM customer")
    customers = cur.fetchone()['c']
    cur.execute("SELECT COUNT(*) AS c FROM orders")
    orders = cur.fetchone()['c']
    cur.execute("SELECT COUNT(*) AS c FROM menu_item WHERE is_available = TRUE")
    menu = cur.fetchone()['c']
    cur.execute("SELECT COUNT(*) AS c FROM employee")
    employees = cur.fetchone()['c']
    cur.execute("SELECT COUNT(*) AS c FROM bill WHERE payment_status = 'Unpaid'")
    unpaid = cur.fetchone()['c']
    cur.close(); conn.close()
    return render_template('index.html',
        customers=customers, orders=orders,
        menu=menu, employees=employees, unpaid=unpaid)

# ════════════════════════════════════════
#  CUSTOMERS
# ════════════════════════════════════════
@app.route('/customers')
def customers():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM customer ORDER BY customer_id")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('customers.html', customers=rows)

@app.route('/customers/add', methods=['GET','POST'])
def add_customer():
    if request.method == 'POST':
        name       = request.form['name']
        contact    = request.form['contact']
        membership = request.form['membership']
        conn = get_db()
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO customer (name, contact, membership, loyalty_pts)
            VALUES (%s, %s, %s, 0)
        """, (name, contact, membership))
        conn.commit(); cur.close(); conn.close()
        flash('Customer added successfully!', 'success')
        return redirect(url_for('customers'))
    return render_template('customer_form.html', action='Add', customer=None)

@app.route('/customers/edit/<int:cid>', methods=['GET','POST'])
def edit_customer(cid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    if request.method == 'POST':
        name       = request.form['name']
        contact    = request.form['contact']
        membership = request.form['membership']
        cur.execute("""
            UPDATE customer SET name=%s, contact=%s, membership=%s
            WHERE customer_id=%s
        """, (name, contact, membership, cid))
        conn.commit(); cur.close(); conn.close()
        flash('Customer updated!', 'success')
        return redirect(url_for('customers'))
    cur.execute("SELECT * FROM customer WHERE customer_id=%s", (cid,))
    customer = cur.fetchone()
    cur.close(); conn.close()
    return render_template('customer_form.html', action='Edit', customer=customer)

@app.route('/customers/delete/<int:cid>')
def delete_customer(cid):
    conn = get_db(); cur = conn.cursor()
    cur.execute("DELETE FROM customer WHERE customer_id=%s", (cid,))
    conn.commit(); cur.close(); conn.close()
    flash('Customer deleted.', 'info')
    return redirect(url_for('customers'))

# ════════════════════════════════════════
#  MENU ITEMS
# ════════════════════════════════════════
@app.route('/menu')
def menu():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM menu_item ORDER BY category, item_name")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('menu.html', items=rows)

@app.route('/menu/add', methods=['GET','POST'])
def add_menu_item():
    if request.method == 'POST':
        name      = request.form['item_name']
        price     = request.form['price']
        category  = request.form['category']
        available = 'is_available' in request.form
        conn = get_db(); cur = conn.cursor()
        cur.execute("""
            INSERT INTO menu_item (item_name, price, category, is_available)
            VALUES (%s, %s, %s, %s)
        """, (name, price, category, available))
        conn.commit(); cur.close(); conn.close()
        flash('Menu item added!', 'success')
        return redirect(url_for('menu'))
    return render_template('menu_form.html', action='Add', item=None)

@app.route('/menu/edit/<int:iid>', methods=['GET','POST'])
def edit_menu_item(iid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    if request.method == 'POST':
        name      = request.form['item_name']
        price     = request.form['price']
        category  = request.form['category']
        available = 'is_available' in request.form
        cur.execute("""
            UPDATE menu_item SET item_name=%s, price=%s, category=%s, is_available=%s
            WHERE item_id=%s
        """, (name, price, category, available, iid))
        conn.commit(); cur.close(); conn.close()
        flash('Menu item updated!', 'success')
        return redirect(url_for('menu'))
    cur.execute("SELECT * FROM menu_item WHERE item_id=%s", (iid,))
    item = cur.fetchone()
    cur.close(); conn.close()
    return render_template('menu_form.html', action='Edit', item=item)

@app.route('/menu/delete/<int:iid>')
def delete_menu_item(iid):
    conn = get_db(); cur = conn.cursor()
    cur.execute("DELETE FROM menu_item WHERE item_id=%s", (iid,))
    conn.commit(); cur.close(); conn.close()
    flash('Menu item deleted.', 'info')
    return redirect(url_for('menu'))

# ════════════════════════════════════════
#  ORDERS
# ════════════════════════════════════════
@app.route('/orders')
def orders():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT o.order_id, o.order_datetime, o.order_status, o.order_type,
               c.name AS customer_name
        FROM orders o
        JOIN customer c ON o.customer_id = c.customer_id
        ORDER BY o.order_datetime DESC
    """)
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('orders.html', orders=rows)

@app.route('/orders/new', methods=['GET','POST'])
def new_order():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    if request.method == 'POST':
        customer_id  = request.form['customer_id']
        order_type   = request.form['order_type']
        item_ids     = request.form.getlist('item_id[]')
        quantities   = request.form.getlist('quantity[]')
        # insert order
        cur.execute("""
            INSERT INTO orders (customer_id, order_status, order_datetime, order_type)
            VALUES (%s, 'Pending', NOW(), %s) RETURNING order_id
        """, (customer_id, order_type))
        order_id = cur.fetchone()['order_id']
        # insert order items
        for iid, qty in zip(item_ids, quantities):
            if iid and qty:
                cur.execute("""
                    INSERT INTO order_item (order_id, item_id, quantity)
                    VALUES (%s, %s, %s)
                """, (order_id, iid, qty))
        conn.commit(); cur.close(); conn.close()
        flash(f'Order #{order_id} placed!', 'success')
        return redirect(url_for('orders'))
    cur.execute("SELECT * FROM customer ORDER BY name")
    customers = cur.fetchall()
    cur.execute("SELECT * FROM menu_item WHERE is_available=TRUE ORDER BY category, item_name")
    menu_items = cur.fetchall()
    cur.close(); conn.close()
    return render_template('order_form.html', customers=customers, menu_items=menu_items)

@app.route('/orders/<int:oid>')
def view_order(oid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT o.*, c.name AS customer_name
        FROM orders o JOIN customer c ON o.customer_id=c.customer_id
        WHERE o.order_id=%s
    """, (oid,))
    order = cur.fetchone()
    cur.execute("""
        SELECT oi.quantity, m.item_name, m.price, (oi.quantity * m.price) AS subtotal
        FROM order_item oi JOIN menu_item m ON oi.item_id=m.item_id
        WHERE oi.order_id=%s
    """, (oid,))
    items = cur.fetchall()
    # check if bill exists
    cur.execute("SELECT * FROM bill WHERE order_id=%s", (oid,))
    bill = cur.fetchone()
    cur.close(); conn.close()
    return render_template('order_detail.html', order=order, items=items, bill=bill)

@app.route('/orders/status/<int:oid>', methods=['POST'])
def update_order_status(oid):
    status = request.form['status']
    conn = get_db(); cur = conn.cursor()
    cur.execute("UPDATE orders SET order_status=%s WHERE order_id=%s", (status, oid))
    conn.commit(); cur.close(); conn.close()
    flash('Order status updated!', 'success')
    return redirect(url_for('view_order', oid=oid))

# ════════════════════════════════════════
#  BILLS
# ════════════════════════════════════════
@app.route('/bills')
def bills():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT b.*, c.name AS customer_name, b.order_id
        FROM bill b
        JOIN orders o ON b.order_id=o.order_id
        JOIN customer c ON o.customer_id=c.customer_id
        ORDER BY b.bill_id DESC
    """)
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('bills.html', bills=rows)

@app.route('/bills/generate/<int:oid>', methods=['GET','POST'])
def generate_bill(oid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    # calculate total from order items
    cur.execute("""
        SELECT SUM(oi.quantity * m.price) AS total
        FROM order_item oi JOIN menu_item m ON oi.item_id=m.item_id
        WHERE oi.order_id=%s
    """, (oid,))
    total = cur.fetchone()['total'] or 0

    if request.method == 'POST':
        payment_mode = request.form['payment_mode']
        promo_code   = request.form.get('promo_code', '').strip()
        discount     = 0
        promo_applied = None

        if promo_code:
            cur.execute("""
                SELECT * FROM valid_promo_code
                WHERE code=%s AND expiry_date >= CURRENT_DATE
                AND %s >= min_order_val
            """, (promo_code, total))
            promo = cur.fetchone()
            if promo:
                if promo['discount_type'] == 'percent':
                    discount = round(total * promo['discount_amount'] / 100, 2)
                else:
                    discount = promo['discount_amount']
                promo_applied = promo_code
                # delete used promo code (business rule)
                cur.execute("DELETE FROM valid_promo_code WHERE code=%s", (promo_code,))
            else:
                flash('Invalid or expired promo code.', 'warning')

        final = max(total - discount, 0)
        cur.execute("""
            INSERT INTO bill (order_id, total_amount, discount_applied, final_amount,
                              payment_mode, payment_status, promo_code_used)
            VALUES (%s, %s, %s, %s, %s, 'Unpaid', %s) RETURNING bill_id
        """, (oid, total, discount, final, payment_mode, promo_applied))
        bill_id = cur.fetchone()['bill_id']
        cur.execute("UPDATE orders SET order_status='Completed' WHERE order_id=%s", (oid,))
        conn.commit(); cur.close(); conn.close()
        flash(f'Bill #{bill_id} generated! Final amount: Rs. {final}', 'success')
        return redirect(url_for('view_bill', bid=bill_id))

    cur.execute("""
        SELECT oi.quantity, m.item_name, m.price, (oi.quantity*m.price) AS subtotal
        FROM order_item oi JOIN menu_item m ON oi.item_id=m.item_id
        WHERE oi.order_id=%s
    """, (oid,))
    items = cur.fetchall()
    cur.execute("SELECT * FROM valid_promo_code WHERE expiry_date >= CURRENT_DATE")
    promos = cur.fetchall()
    cur.close(); conn.close()
    return render_template('bill_form.html', oid=oid, total=total, items=items, promos=promos)

@app.route('/bills/<int:bid>')
def view_bill(bid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT b.*, c.name AS customer_name, o.order_type, o.order_datetime
        FROM bill b
        JOIN orders o ON b.order_id=o.order_id
        JOIN customer c ON o.customer_id=c.customer_id
        WHERE b.bill_id=%s
    """, (bid,))
    bill = cur.fetchone()
    cur.execute("""
        SELECT oi.quantity, m.item_name, m.price, (oi.quantity*m.price) AS subtotal
        FROM order_item oi JOIN menu_item m ON oi.item_id=m.item_id
        WHERE oi.order_id=%s
    """, (bill['order_id'],))
    items = cur.fetchall()
    cur.close(); conn.close()
    return render_template('bill_detail.html', bill=bill, items=items)

@app.route('/bills/pay/<int:bid>')
def mark_paid(bid):
    conn = get_db(); cur = conn.cursor()
    cur.execute("UPDATE bill SET payment_status='Paid' WHERE bill_id=%s", (bid,))
    conn.commit(); cur.close(); conn.close()
    flash('Bill marked as paid!', 'success')
    return redirect(url_for('view_bill', bid=bid))

# ════════════════════════════════════════
#  PROMO CODES
# ════════════════════════════════════════
@app.route('/promos')
def promos():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM valid_promo_code ORDER BY expiry_date")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('promos.html', promos=rows)

@app.route('/promos/add', methods=['GET','POST'])
def add_promo():
    if request.method == 'POST':
        code           = request.form['code']
        discount_type  = request.form['discount_type']
        discount_amt   = request.form['discount_amount']
        expiry         = request.form['expiry_date']
        min_order      = request.form['min_order_val']
        conn = get_db(); cur = conn.cursor()
        cur.execute("""
            INSERT INTO valid_promo_code
            (code, discount_type, discount_amount, expiry_date, min_order_val)
            VALUES (%s, %s, %s, %s, %s)
        """, (code, discount_type, discount_amt, expiry, min_order))
        conn.commit(); cur.close(); conn.close()
        flash('Promo code added!', 'success')
        return redirect(url_for('promos'))
    return render_template('promo_form.html')

@app.route('/promos/delete/<string:code>')
def delete_promo(code):
    conn = get_db(); cur = conn.cursor()
    cur.execute("DELETE FROM valid_promo_code WHERE code=%s", (code,))
    conn.commit(); cur.close(); conn.close()
    flash('Promo code deleted.', 'info')
    return redirect(url_for('promos'))

# ════════════════════════════════════════
#  EMPLOYEES
# ════════════════════════════════════════
@app.route('/employees')
def employees():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM employee ORDER BY role, emp_name")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('employees.html', employees=rows)

@app.route('/employees/add', methods=['GET','POST'])
def add_employee():
    if request.method == 'POST':
        name   = request.form['emp_name']
        dob    = request.form['dob']
        role   = request.form['role']
        salary = request.form['salary']
        conn = get_db(); cur = conn.cursor()
        cur.execute("""
            INSERT INTO employee (emp_name, dob, role, salary)
            VALUES (%s, %s, %s, %s)
        """, (name, dob, role, salary))
        conn.commit(); cur.close(); conn.close()
        flash('Employee added!', 'success')
        return redirect(url_for('employees'))
    return render_template('employee_form.html', action='Add', employee=None)

@app.route('/employees/edit/<int:eid>', methods=['GET','POST'])
def edit_employee(eid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    if request.method == 'POST':
        name   = request.form['emp_name']
        dob    = request.form['dob']
        role   = request.form['role']
        salary = request.form['salary']
        cur.execute("""
            UPDATE employee SET emp_name=%s, dob=%s, role=%s, salary=%s
            WHERE employee_id=%s
        """, (name, dob, role, salary, eid))
        conn.commit(); cur.close(); conn.close()
        flash('Employee updated!', 'success')
        return redirect(url_for('employees'))
    cur.execute("SELECT * FROM employee WHERE employee_id=%s", (eid,))
    employee = cur.fetchone()
    cur.close(); conn.close()
    return render_template('employee_form.html', action='Edit', employee=employee)

@app.route('/employees/delete/<int:eid>')
def delete_employee(eid):
    conn = get_db(); cur = conn.cursor()
    cur.execute("DELETE FROM employee WHERE employee_id=%s", (eid,))
    conn.commit(); cur.close(); conn.close()
    flash('Employee deleted.', 'info')
    return redirect(url_for('employees'))

# ════════════════════════════════════════
#  AUDIT LOG
# ════════════════════════════════════════
@app.route('/audit')
def audit():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM audit_log ORDER BY change_timestamp DESC LIMIT 100")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('audit.html', logs=rows)

if __name__ == '__main__':
    app.run(debug=True)
