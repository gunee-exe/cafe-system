from flask import Flask, render_template, request, redirect, url_for, flash, jsonify, session
from functools import wraps
import psycopg2
import psycopg2.extras
 
app = Flask(__name__)
app.secret_key = 'cafe_secret_key_2024'
 
DB_CONFIG = {
    'host': 'localhost',
    'database': 'cafe_db',
    'user': 'postgres',
    'password': 'mianusman1',
    'port': '5432'
}
 
def get_db():
    return psycopg2.connect(**DB_CONFIG)
 
# ─── AUTH HELPERS ────────────────────────────────────────────────
 
def login_required(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        if 'employee_id' not in session:
            flash('Please log in first.', 'warning')
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated
 
def role_required(*roles):
    def decorator(f):
        @wraps(f)
        def decorated(*args, **kwargs):
            if 'employee_id' not in session:
                flash('Please log in first.', 'warning')
                return redirect(url_for('login'))
            if session.get('role') not in roles:
                flash('You do not have permission to access that page.', 'danger')
                return redirect(url_for('index'))
            return f(*args, **kwargs)
        return decorated
    return decorator
 
# ─── LOGIN / LOGOUT ──────────────────────────────────────────────
 
@app.route('/login', methods=['GET', 'POST'])
def login():
    if 'employee_id' in session:
        return redirect(url_for('index'))
    if request.method == 'POST':
        name     = request.form.get('emp_name', '').strip()
        password = request.form.get('password', '').strip()
        conn = get_db()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        cur.execute(
            "SELECT employee_id, emp_name, role FROM employee WHERE emp_name=%s AND password=%s",
            (name, password)
        )
        emp = cur.fetchone()
        cur.close(); conn.close()
        if emp:
            session['employee_id'] = emp['employee_id']
            session['emp_name']    = emp['emp_name']
            session['role']        = emp['role']
            flash(f'Welcome back, {emp["emp_name"]}!', 'success')
            return redirect(url_for('index'))
        else:
            flash('Invalid name or password.', 'danger')
    return render_template('login.html')
 
@app.route('/logout')
def logout():
    session.clear()
    flash('You have been logged out.', 'info')
    return redirect(url_for('login'))
 
# ════════════════════════════════════════
#  HOME
# ════════════════════════════════════════
@app.route('/')
@login_required
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
#  CUSTOMERS  (Cashier view-only, Manager full)
# ════════════════════════════════════════
@app.route('/customers')
@role_required('Cashier', 'Manager')
def customers():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM customer ORDER BY customer_id")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('customers.html', customers=rows)
 
@app.route('/customers/add', methods=['GET', 'POST'])
@role_required('Manager')
def add_customer():
    if request.method == 'POST':
        name       = request.form['name']
        contact    = request.form['contact']
        membership = request.form['membership']
        conn = get_db(); cur = conn.cursor()
        cur.execute("INSERT INTO customer (name, contact, membership, loyalty_pts) VALUES (%s,%s,%s,0)",
                    (name, contact, membership))
        conn.commit(); cur.close(); conn.close()
        flash('Customer added!', 'success')
        return redirect(url_for('customers'))
    return render_template('customer_form.html', action='Add', customer=None)
 
@app.route('/customers/edit/<int:cid>', methods=['GET', 'POST'])
@role_required('Manager')
def edit_customer(cid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    if request.method == 'POST':
        name       = request.form['name']
        contact    = request.form['contact']
        membership = request.form['membership']
        cur.execute("UPDATE customer SET name=%s,contact=%s,membership=%s WHERE customer_id=%s",
                    (name, contact, membership, cid))
        conn.commit(); cur.close(); conn.close()
        flash('Customer updated!', 'success')
        return redirect(url_for('customers'))
    cur.execute("SELECT * FROM customer WHERE customer_id=%s", (cid,))
    customer = cur.fetchone()
    cur.close(); conn.close()
    return render_template('customer_form.html', action='Edit', customer=customer)
 
@app.route('/customers/delete/<int:cid>')
@role_required('Manager')
def delete_customer(cid):
    conn = get_db(); cur = conn.cursor()
    cur.execute("DELETE FROM customer WHERE customer_id=%s", (cid,))
    conn.commit(); cur.close(); conn.close()
    flash('Customer deleted.', 'info')
    return redirect(url_for('customers'))
 
# ════════════════════════════════════════
#  MENU  (all view, Manager edits)
# ════════════════════════════════════════
@app.route('/menu')
@login_required
def menu():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM menu_item ORDER BY category, item_name")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('menu.html', items=rows)
 
@app.route('/menu/add', methods=['GET', 'POST'])
@role_required('Manager')
def add_menu_item():
    if request.method == 'POST':
        name      = request.form['item_name']
        price     = request.form['price']
        category  = request.form['category']
        available = 'is_available' in request.form
        conn = get_db(); cur = conn.cursor()
        cur.execute("INSERT INTO menu_item (item_name,price,category,is_available) VALUES (%s,%s,%s,%s)",
                    (name, price, category, available))
        conn.commit(); cur.close(); conn.close()
        flash('Menu item added!', 'success')
        return redirect(url_for('menu'))
    return render_template('menu_form.html', action='Add', item=None)
 
@app.route('/menu/edit/<int:iid>', methods=['GET', 'POST'])
@role_required('Manager')
def edit_menu_item(iid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    if request.method == 'POST':
        name      = request.form['item_name']
        price     = request.form['price']
        category  = request.form['category']
        available = 'is_available' in request.form
        cur.execute("UPDATE menu_item SET item_name=%s,price=%s,category=%s,is_available=%s WHERE item_id=%s",
                    (name, price, category, available, iid))
        conn.commit(); cur.close(); conn.close()
        flash('Menu item updated!', 'success')
        return redirect(url_for('menu'))
    cur.execute("SELECT * FROM menu_item WHERE item_id=%s", (iid,))
    item = cur.fetchone()
    cur.close(); conn.close()
    return render_template('menu_form.html', action='Edit', item=item)
 
@app.route('/menu/delete/<int:iid>')
@role_required('Manager')
def delete_menu_item(iid):
    conn = get_db(); cur = conn.cursor()
    cur.execute("DELETE FROM menu_item WHERE item_id=%s", (iid,))
    conn.commit(); cur.close(); conn.close()
    flash('Menu item deleted.', 'info')
    return redirect(url_for('menu'))
 
# ════════════════════════════════════════
#  ORDERS  (all roles)
# ════════════════════════════════════════
@app.route('/orders')
@login_required
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
 
@app.route('/api/customer-by-mobile')
@login_required
def customer_by_mobile():
    contact = request.args.get('contact', '').strip()
    if not contact:
        return jsonify({'found': False})
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT customer_id, name, membership, loyalty_pts FROM customer WHERE contact=%s", (contact,))
    row = cur.fetchone()
    cur.close(); conn.close()
    if row:
        return jsonify({'found': True, 'customer_id': row['customer_id'],
                        'name': row['name'], 'membership': row['membership'],
                        'loyalty_pts': row['loyalty_pts']})
    return jsonify({'found': False})
 
@app.route('/orders/new', methods=['GET', 'POST'])
@login_required
def new_order():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    if request.method == 'POST':
        contact    = request.form.get('contact', '').strip()
        new_name   = request.form.get('new_customer_name', '').strip()
        order_type = request.form['order_type']
        item_ids   = request.form.getlist('item_id[]')
        quantities = request.form.getlist('quantity[]')
 
        cur.execute("SELECT customer_id FROM customer WHERE contact=%s", (contact,))
        existing = cur.fetchone()
        if existing:
            customer_id = existing['customer_id']
        else:
            cur.execute("""
                INSERT INTO customer (name, contact, membership, loyalty_pts)
                VALUES (%s, %s, 'Regular', 0) RETURNING customer_id
            """, (new_name or 'Guest', contact))
            customer_id = cur.fetchone()['customer_id']
            flash(f'New customer "{new_name or "Guest"}" registered automatically!', 'info')
 
        try:
            cur.execute("""
                INSERT INTO orders (customer_id, order_status, order_datetime, order_type)
                VALUES (%s, 'Pending', NOW(), %s) RETURNING order_id
            """, (customer_id, order_type))
            order_id = cur.fetchone()['order_id']
        except Exception as e:
            conn.rollback(); cur.close(); conn.close()
            flash(str(e).split('\n')[0], 'danger')
            return redirect(url_for('new_order'))
 
        for iid, qty in zip(item_ids, quantities):
            if iid and qty:
                cur.execute("INSERT INTO order_item (order_id, item_id, quantity) VALUES (%s,%s,%s)",
                            (order_id, iid, qty))
        conn.commit(); cur.close(); conn.close()
        flash(f'Order #{order_id} placed!', 'success')
        return redirect(url_for('orders'))
 
    cur.execute("SELECT * FROM menu_item WHERE is_available=TRUE ORDER BY category, item_name")
    menu_items = cur.fetchall()
    cur.close(); conn.close()
    return render_template('order_form.html', menu_items=menu_items)
 
@app.route('/orders/<int:oid>')
@login_required
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
    cur.execute("SELECT * FROM bill WHERE order_id=%s", (oid,))
    bill = cur.fetchone()
    cur.close(); conn.close()
    return render_template('order_detail.html', order=order, items=items, bill=bill)
 
@app.route('/orders/status/<int:oid>', methods=['POST'])
@login_required
def update_order_status(oid):
    status = request.form['status']
    conn = get_db(); cur = conn.cursor()
    cur.execute("UPDATE orders SET order_status=%s WHERE order_id=%s", (status, oid))
    conn.commit(); cur.close(); conn.close()
    flash('Order status updated!', 'success')
    return redirect(url_for('view_order', oid=oid))
 
# ════════════════════════════════════════
#  BILLS  (Cashier + Manager)
# ════════════════════════════════════════
@app.route('/bills')
@role_required('Cashier', 'Manager')
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
 
@app.route('/bills/generate/<int:oid>', methods=['GET', 'POST'])
@role_required('Cashier', 'Manager')
def generate_bill(oid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("""
        SELECT SUM(oi.quantity * m.price) AS total
        FROM order_item oi JOIN menu_item m ON oi.item_id=m.item_id
        WHERE oi.order_id=%s
    """, (oid,))
    total = cur.fetchone()['total'] or 0
 
    if request.method == 'POST':
        payment_mode  = request.form['payment_mode']
        promo_code    = request.form.get('promo_code', '').strip()
        discount      = 0
        promo_applied = None
 
        if promo_code:
            cur.execute("""
                SELECT * FROM valid_promo_code
                WHERE code=%s AND expiry_date >= CURRENT_DATE AND %s >= min_order_val
            """, (promo_code, total))
            promo = cur.fetchone()
            if promo:
                if promo['discount_type'] == 'percent':
                    discount = round(total * promo['discount_amount'] / 100, 2)
                else:
                    discount = promo['discount_amount']
                promo_applied = promo_code
                cur.execute("DELETE FROM valid_promo_code WHERE code=%s", (promo_code,))
            else:
                flash('Invalid or expired promo code.', 'warning')
 
        final = max(total - discount, 0)
        cur.execute("""
            INSERT INTO bill (order_id, total_amount, discount_applied, final_amount,
                              payment_mode, payment_status, promo_code_used)
            VALUES (%s,%s,%s,%s,%s,'Unpaid',%s) RETURNING bill_id
        """, (oid, total, discount, final, payment_mode, promo_applied))
        bill_id = cur.fetchone()['bill_id']
        cur.execute("UPDATE orders SET order_status='Completed' WHERE order_id=%s", (oid,))
        conn.commit(); cur.close(); conn.close()
        flash(f'Bill #{bill_id} generated! Final: Rs. {final}', 'success')
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
@role_required('Cashier', 'Manager')
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
@role_required('Cashier', 'Manager')
def mark_paid(bid):
    conn = get_db(); cur = conn.cursor()
    cur.execute("UPDATE bill SET payment_status='Paid' WHERE bill_id=%s", (bid,))
    conn.commit(); cur.close(); conn.close()
    flash('Bill marked as paid!', 'success')
    return redirect(url_for('view_bill', bid=bid))
 
# ════════════════════════════════════════
#  PROMOS  (Manager only)
# ════════════════════════════════════════
@app.route('/promos')
@role_required('Manager')
def promos():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM valid_promo_code ORDER BY expiry_date")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('promos.html', promos=rows)
 
@app.route('/promos/add', methods=['GET', 'POST'])
@role_required('Manager')
def add_promo():
    if request.method == 'POST':
        code          = request.form['code']
        discount_type = request.form['discount_type']
        discount_amt  = request.form['discount_amount']
        expiry        = request.form['expiry_date']
        min_order     = request.form['min_order_val']
        conn = get_db(); cur = conn.cursor()
        cur.execute("""
            INSERT INTO valid_promo_code (code, discount_type, discount_amount, expiry_date, min_order_val)
            VALUES (%s,%s,%s,%s,%s)
        """, (code, discount_type, discount_amt, expiry, min_order))
        conn.commit(); cur.close(); conn.close()
        flash('Promo code added!', 'success')
        return redirect(url_for('promos'))
    return render_template('promo_form.html')
 
@app.route('/promos/delete/<string:code>')
@role_required('Manager')
def delete_promo(code):
    conn = get_db(); cur = conn.cursor()
    cur.execute("DELETE FROM valid_promo_code WHERE code=%s", (code,))
    conn.commit(); cur.close(); conn.close()
    flash('Promo code deleted.', 'info')
    return redirect(url_for('promos'))
 
# ════════════════════════════════════════
#  EMPLOYEES  (Manager only)
# ════════════════════════════════════════
@app.route('/employees')
@role_required('Manager')
def employees():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM employee ORDER BY role, emp_name")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('employees.html', employees=rows)
 
@app.route('/employees/add', methods=['GET', 'POST'])
@role_required('Manager')
def add_employee():
    if request.method == 'POST':
        name     = request.form['emp_name']
        dob      = request.form['dob']
        role     = request.form['role']
        salary   = request.form['salary']
        password = request.form['password']
        conn = get_db(); cur = conn.cursor()
        cur.execute("INSERT INTO employee (emp_name, dob, role, salary, password) VALUES (%s,%s,%s,%s,%s)",
                    (name, dob, role, salary, password))
        conn.commit(); cur.close(); conn.close()
        flash('Employee added!', 'success')
        return redirect(url_for('employees'))
    return render_template('employee_form.html', action='Add', employee=None)
 
@app.route('/employees/edit/<int:eid>', methods=['GET', 'POST'])
@role_required('Manager')
def edit_employee(eid):
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    if request.method == 'POST':
        name     = request.form['emp_name']
        dob      = request.form['dob']
        role     = request.form['role']
        salary   = request.form['salary']
        password = request.form.get('password', '').strip()
        if password:
            cur.execute("UPDATE employee SET emp_name=%s,dob=%s,role=%s,salary=%s,password=%s WHERE employee_id=%s",
                        (name, dob, role, salary, password, eid))
        else:
            cur.execute("UPDATE employee SET emp_name=%s,dob=%s,role=%s,salary=%s WHERE employee_id=%s",
                        (name, dob, role, salary, eid))
        conn.commit(); cur.close(); conn.close()
        flash('Employee updated!', 'success')
        return redirect(url_for('employees'))
    cur.execute("SELECT * FROM employee WHERE employee_id=%s", (eid,))
    employee = cur.fetchone()
    cur.close(); conn.close()
    return render_template('employee_form.html', action='Edit', employee=employee)
 
@app.route('/employees/delete/<int:eid>')
@role_required('Manager')
def delete_employee(eid):
    conn = get_db(); cur = conn.cursor()
    cur.execute("DELETE FROM employee WHERE employee_id=%s", (eid,))
    conn.commit(); cur.close(); conn.close()
    flash('Employee deleted.', 'info')
    return redirect(url_for('employees'))
 
# ════════════════════════════════════════
#  AUDIT LOG  (Manager only)
# ════════════════════════════════════════
@app.route('/audit')
@role_required('Manager')
def audit():
    conn = get_db()
    cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
    cur.execute("SELECT * FROM audit_log ORDER BY change_timestamp DESC LIMIT 100")
    rows = cur.fetchall()
    cur.close(); conn.close()
    return render_template('audit.html', logs=rows)
 
if __name__ == '__main__':
    app.run(debug=True)