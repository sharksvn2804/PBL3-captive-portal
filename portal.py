from flask import Flask, request, render_template, redirect
import subprocess, json, os, logging, time

app = Flask(__name__, template_folder='templates', static_folder='static')
LOGIN_FILE = "logged_in.json"
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Load DB ---
if os.path.exists(LOGIN_FILE):
    try:
        logged_ips = set(json.load(open(LOGIN_FILE, encoding="utf-8")))
    except:
        logged_ips = set()
else:
    logged_ips = set()

def save_db():
    json.dump(list(logged_ips), open(LOGIN_FILE, "w", encoding="utf-8"))

def is_logged(ip):
    return ip in logged_ips

def allow_ip(ip):
    subprocess.run(["sudo", "ipset", "add", "logged_in", ip], check=False)
    logged_ips.add(ip)
    save_db()
    logger.info(f"[+] Allowed {ip}")
    # Xóa connection tracking để iptables nhận IP mới ngay
    subprocess.run(["sudo", "conntrack", "-D", "-s", ip], check=False)

CAPTIVE_PATHS = ["/generate_204", "/gen_204", "/hotspot-detect.html", "/"]

# -----------------------------
# TRANG CHÍNH (Login portal)
# -----------------------------
@app.route("/", methods=["GET"])
def index():
    ip = request.remote_addr
    if is_logged(ip):
        # IP đã login → chuyển hướng ngay (tránh bị kẹt ở /)
        return redirect("http://idu.vn")
    return render_template("index.html")

# -----------------------------
# LOGIN POST
# -----------------------------
@app.route("/login", methods=["POST"])
def login():
    ip = request.remote_addr
    user = request.form.get("user", "").strip()
    passwd = request.form.get("pass", "").strip()

    if user == "khanh" and passwd == "1234":
        allow_ip(ip)
        time.sleep(0.5)
        return render_template("success.html", ip=ip)

    # Login failed → dùng template fail.html
    return render_template("fail.html", ip=ip)

# -----------------------------
# TRANG SUCCESS
# -----------------------------
@app.route("/success", methods=["GET"])
def success():
    ip = request.remote_addr
    if is_logged(ip):
        # Chuyển hướng ra ngoài internet → dùng redirect.html
        return render_template("redirect.html", url="http://idu.vn")
    return render_template("index.html")

# -----------------------------
# CATCH-ALL
# -----------------------------
@app.route("/<path:path>")
def catch_all(path):
    ip = request.remote_addr
    full_path = "/" + path

    # Nếu đã login, trả về 204 để hoàn thành Captive Check, hoặc cho phép trình duyệt đi tiếp.
    if is_logged(ip):
        return "", 204
        
    # Nếu chưa login:
    # 1. request từ captive check Android/iOS
    if full_path in CAPTIVE_PATHS:
        return render_template("index.html") # Phải trả về trang login

    # 2. Các request khác bị DNAT về đây (trừ request tới idu.vn)
    return render_template("index.html")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=80, debug=False, threaded=True)