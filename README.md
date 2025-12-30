HƯỚNG DẪN SỬ DỤNG PBL3 – HỆ THỐNG CAPTIVE PORTAL

(Dành cho các thành viên trong nhóm thực hiện đồ án)

Bước 1: Truy cập thư mục chứa mã nguồn

Mở Terminal và di chuyển đến thư mục chứa mã nguồn của hệ thống Captive Portal đã được tải về trước đó.
Ví dụ:

cd ~/captive_portal

Bước 2: Khởi chạy hệ thống Captive Portal

Thực thi script khởi tạo hệ thống với quyền quản trị (sudo):

sudo bash setup_captive.sh


Chờ cho đến khi script thực thi hoàn tất hoàn toàn trước khi tiếp tục các bước tiếp theo.

Bước 3: Kiểm tra gói tin mạng (tùy chọn)

Trong trường hợp cần theo dõi hoặc kiểm tra lưu lượng mạng, có thể sử dụng công cụ tcpdump.
Lưu ý: cần thay đổi tên interface mạng cho phù hợp với adapter USB mạng của từng máy.

Ví dụ:

sudo tcpdump -i wlxa047d7605b5a tcp

Bước 4: Dừng Captive Portal và khôi phục kết nối Internet

Sau khi hoàn thành quá trình kiểm thử, để khôi phục lại trạng thái kết nối Internet ban đầu của máy, thực thi lệnh:

sudo bash stop_captive.sh

LƯU Ý QUAN TRỌNG

Thư mục template phải được đổi tên thành templates để tránh lỗi khi chạy hệ thống.

Cần thay đổi tên interface mạng cho đúng với USB mạng đang sử dụng trên từng máy.
Có thể kiểm tra tên interface bằng lệnh:

ip link


Sau đó sao chép (Ctrl+C) và thay thế tên interface tương ứng vào các file cấu hình và script có liên quan.

Đảm bảo tất cả các thay đổi interface được thực hiện đồng bộ trong toàn bộ mã nguồn để tránh lỗi khi vận hành.
