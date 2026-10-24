# Econ City: mục tiêu và người dùng

## Ai dùng

- Học sinh THCS, THPT (có thể cả sinh viên), chơi trong giờ học hoặc ở nhà theo lớp giáo viên tạo. Mỗi em xây một
  thành phố trên lưới 12x12 trong 24 tháng, đặt thuế và tìm hiểu vì sao dân đến hay bỏ đi.
- Giáo viên: tạo lớp, theo dõi tiến độ từng học sinh, gán sự kiện (suy thoái, đại dịch...), xuất CSV, mở phòng học riêng.
- Chủ game: quản lý danh sách giáo viên, cấm người chơi, xoá dữ liệu khi có yêu cầu.

## Game để làm gì

Học sinh làm thị trưởng, tự quy hoạch thành phố và đặt thuế. Điều cần các em tự rút ra qua thành phố của mình:

- có việc làm thì dân mới đến,
- dịch vụ công (bệnh viện, trường, công viên) làm dân vui,
- shop cần hàng từ nhà máy,
- thuế cao quá thì dân bỏ đi và thành phố thu về ít hơn (đường cong Laffer).

Giáo viên cần đo được tiến độ của từng em. Luật chơi đơn giản và kiểm chứng được (docs/luat-choi-moi.md, bản Luau
khớp từng con số với bản thử JS), gắn với công cụ lớp học (mã lớp, tiến độ, sự kiện, CSV). Đây không phải game xây
thành phố để giải trí thuần tuý.

## Bối cảnh dùng

- Chơi theo lớp: giáo viên đưa mã lớp, học sinh vào game, giáo viên gán sự kiện cho cả lớp.
- Một ván 24 tháng, 20 giây một tháng (khoảng 8 phút), có tạm dừng, lúc tạm dừng vẫn xây được.
- Học sinh ở Việt Nam chơi qua Roblox do VNG phát hành. Toàn bộ chữ trong game là tiếng Việt.
- Máy trong lớp thường yếu, nhiều em dùng điện thoại: game phải chạy được trên máy yếu, chữ đọc được trên điện thoại,
  dùng được bằng cảm ứng và tay cầm.

## Ràng buộc

- Luật và số liệu nằm trong `src/shared/Config.luau` và `CityEngine.luau`. Server kiểm tra lại mọi thao tác.
- Không hỏi email, mật khẩu, tên thật (quy định của Roblox). Chữ người dùng nhập phải qua bộ lọc của Roblox.
- Chưa tải lên Roblox ảnh, icon hay mô hình riêng nào. Mọi hình đều dựng bằng Part và chữ.
- Tên game là Econ City. Chưa có logo, màu hay font bắt buộc.

## Nguyên tắc

1. Học sinh nhìn thấy kết quả ngay trên thành phố của mình, không phải đọc giải thích dài.
2. Lúc nào cũng có một việc chính rõ ràng (xây, bắt đầu, đặt thuế). Ít chữ, phản hồi bằng hình là chính.
3. Số liệu hiện ra phải đúng với luật.
