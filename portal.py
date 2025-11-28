# Khai báo các thư viện:
from flask import Flask, request, render_template, redirect, url_for
import json, subprocess, os, logging

# Cơ sở dữ liệu đăng nhập và chương trình mình đang chạy:
app = Flask(__name__, template_folder='templates')
LOGIN_FILE = '/home/khanh/captive_lab/logged_in.json'

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('portal')

# Load danh sách máy khách đăng nhập từ json:
if os.path.exists(LOGIN_FILE):
    with open(LOGIN_FILE,'r') as f:
        try:
            logged_in = json.load(f)
        except:
            logged_in = {}
else:
    logged_in = {}

def save_logged_in():
    with open(LOGIN_FILE,'w') as f:
        json.dump(logged_in,f)

def is_logged_in(ip):
    return logged_in.get(ip, False)

def add_client(ip):
    if not is_logged_in(ip):
        logged_in[ip] = True
        save_logged_in()
        subprocess.run(["sudo","ipset","add","logged_in", ip], check=False)
        subprocess.run(["sudo","conntrack","-D","-s", ip], check=False)
        subprocess.run(["sudo","conntrack","-D","-d", ip], check=False)
        logger.info(f"Client {ip} LOGIN OK")

@app.route('/')
def index():
    ip = request.remote_addr
    if is_logged_in(ip):
        return redirect("/success")
    return render_template('index.html')

@app.route('/login', methods=['POST'])
def login():
    ip = request.remote_addr
    user = request.form.get('user','')
    passwd = request.form.get('pass','')
    logger.info(f"Login attempt: {ip} — {user}")

    if user == "khanh" and passwd == "1234":
        add_client(ip)
        return render_template('success.html')
    return render_template('fail.html')

@app.route('/success')
def success():
    ip = request.remote_addr
    if not is_logged_in(ip):
        return redirect("/")
    return render_template("success.html", redirect_url="http://idu.vn")

@app.route('/<path:any>')
def catch_all(any):
    ip = request.remote_addr
    if not is_logged_in(ip):
        return redirect("/")
    return f"OK: {any}"

if __name__=="__main__":
    app.run(host="0.0.0.0", port=8080, debug=False, threaded=True)
