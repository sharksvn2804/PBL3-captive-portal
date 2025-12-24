# Khai báo các thư viện:
from flask import Flask, request, render_template, redirect, url_for
import json, subprocess, os, logging, threading, time

# Cơ sở dữ liệu đăng nhập và chương trình mình đang chạy:
app = Flask(__name__, template_folder='templates')
LOGIN_FILE = '/home/khanh/PBL3_duphong/logged_in.json'

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger('portal')

# Dữ liệu trong RAM (nhanh hơn file)
logged_in = {}
login_lock = threading.Lock()

# Load dữ liệu từ file lúc khởi động (chỉ 1 lần)
if os.path.exists(LOGIN_FILE):
    try:
        with open(LOGIN_FILE, 'r') as f:
            logged_in = json.load(f)
            logger.info(f"Loaded {len(logged_in)} clients from file")
    except json.JSONDecodeError:
        logger.warning("File corrupted, starting fresh")
        logged_in = {}
else:
    logged_in = {}

# Hàm lưu file ngay lập tức (thread-safe)
def save_to_file():
    """Lưu dữ liệu vào file ngay lập tức"""
    try:
        with open(LOGIN_FILE, 'w') as f:
            json.dump(logged_in, f, indent=2)
        logger.debug(f"Saved {len(logged_in)} clients to file")
    except Exception as e:
        logger.error(f"Failed to save: {e}")

# Background thread: Tự động lưu file mỗi 30 giây
def auto_save_worker():
    """Chạy ở background, lưu dữ liệu định kỳ"""
    while True:
        time.sleep(30)  # Chờ 30 giây
        with login_lock:
            save_to_file()

# Khởi động background thread
save_thread = threading.Thread(target=auto_save_worker, daemon=True)
save_thread.start()

# Thread-safe: Kiểm tra nếu đã đăng nhập hay chưa
def is_logged_in(ip):
    with login_lock:
        if ip not in logged_in:
            return False
        data = logged_in[ip]
        current_time = time.time()
        
        # Session timeout: 24 giờ
        if current_time - data.get("login_time", 0) > 86400:
            del logged_in[ip]
            save_to_file()  # Lưu ngay khi xóa session
            logger.info(f"Session expired: {ip}")
            return False
        
        # Idle timeout: 30 phút
        if current_time - data.get("last_activity", 0) > 1800:
            del logged_in[ip]
            save_to_file()  # Lưu ngay khi xóa session
            logger.info(f"Idle timeout: {ip}")
            return False
        
        # Update last activity
        data["last_activity"] = current_time
        return True

# Thread-safe: Thêm máy khách
def add_client(ip):
    # Thread-safe: Lock trước khi sửa dữ liệu
    with login_lock:
        if ip not in logged_in:
            logged_in[ip] = {
                "login_time": time.time(),
                "last_activity": time.time(),
                "requests": 0
            }
            logger.info(f"New client: {ip}")
        else:
            logged_in[ip]["last_activity"] = time.time()
            logger.info(f"Re-login: {ip}")
        
        # Lưu ngay vào file
        save_to_file()
    
    # Add vào ipset (ngoài lock để không block)
    # Dùng Popen cho speed (không chờ output)
    subprocess.Popen(["sudo", "ipset", "add", "logged_in", ip], 
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    
    logger.info(f"Client {ip} UNLOCKED")

# Thread-safe: Xóa máy khách
def remove_client(ip):
    with login_lock:
        if ip in logged_in:
            del logged_in[ip]
            save_to_file()  # Lưu ngay khi xóa
    
    subprocess.Popen(["sudo", "ipset", "del", "logged_in", ip],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    logger.info(f"Client removed: {ip}")

# Background cleanup: Xóa session hết hạn mỗi 5 phút
def cleanup_expired_sessions():
    """Chạy mỗi 5 phút để xóa session hết hạn"""
    while True:
        time.sleep(300)  # 5 phút
        current_time = time.time()
        
        with login_lock:
            expired_ips = []
            for ip, data in logged_in.items():
                # Check timeout
                if (current_time - data["login_time"] > 86400 or
                    current_time - data["last_activity"] > 1800):
                    expired_ips.append(ip)
            
            # Xóa các IP hết hạn
            if expired_ips:
                for ip in expired_ips:
                    del logged_in[ip]
                    subprocess.Popen(["sudo", "ipset", "del", "logged_in", ip],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                    logger.info(f"Expired: {ip}")
                
                # Lưu file sau khi xóa các session hết hạn
                save_to_file()

# Khởi động cleanup thread
cleanup_thread = threading.Thread(target=cleanup_expired_sessions, daemon=True)
cleanup_thread.start()

# Routes:
@app.after_request
def no_cache(response):
    response.headers['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
    response.headers['Pragma'] = 'no-cache'
    return response

# Dẫn hướng: Trang chủ
@app.route('/')
def index():
    ip = request.remote_addr
    if is_logged_in(ip):
        return redirect("/success", code=302)
    return render_template('index.html')

# Dẫn hướng: Login
@app.route('/login', methods=['POST'])
def login():
    ip = request.remote_addr
    user = request.form.get('user', '')
    passwd = request.form.get('pass', '')
    
    # Kiểm tra thông tin đăng nhập
    if user == "khanh" and passwd == "1234":
        add_client(ip)
        # Redirect ngay tới idu.vn (nhanh hơn render template)
        return redirect("http://idu.vn", code=302)
    
    logger.warning(f"Failed: {ip}")
    return render_template('fail.html')

# Dẫn hướng: Thành công
@app.route('/success')
def success():
    ip = request.remote_addr
    if not is_logged_in(ip):
        return redirect("/", code=302)
    return redirect("http://idu.vn", code=302)

# Dẫn hướng: Catch all
@app.route('/<path:any>')
def catch_all(any):
    ip = request.remote_addr
    if not is_logged_in(ip):
        return redirect("/")
    return f"OK: {any}"

# Main:
if __name__ == "__main__":
    logger.info("Starting Captive Portal Server...")
    try:
        # Use faster WSGI server (Werkzeug is faster than Flask default)
        app.run(
            host="0.0.0.0", 
            port=8080, 
            debug=False, 
            threaded=True,
            use_reloader=False,  # Disable reloader for speed
            use_debugger=False   # Disable debugger for speed
        )
    except KeyboardInterrupt:
        logger.info("Shutting down...")
