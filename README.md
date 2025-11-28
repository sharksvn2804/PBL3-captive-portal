Hướng dẫn sử dụng PBL3 – Captive Portal

Bước 1: Mở terminal và di chuyển vào đúng thư mục chứa code đã tải về.
(Ví dụ: cd ~/captive_portal)

Bước 2: Chạy script khởi chạy Captive Portal với quyền sudo:

sudo bash setup_captive.sh


⇒ Chờ script chạy xong hoàn toàn.

Bước 3: Nếu cần kiểm tra gói tin, dùng lệnh tcpdump (sửa tên interface theo adapter của mỗi người):

sudo tcpdump -i wlxa047d7605b5a tcp


Bước 4: Nếu muốn phục hồi Internet như ban đầu, chạy:

sudo bash stop_captive.sh


LƯU Ý: ĐỔI TÊN TEMPLATE THÀNH TEMPLATES (Tránh lỗi)
