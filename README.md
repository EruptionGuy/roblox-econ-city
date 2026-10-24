# Econ City (Roblox)

Game học kinh tế cho học sinh. Mỗi em làm thị trưởng một thành phố 12x12 ô trong 24 tháng: xây nhà, shop, nhà máy,
trường, bệnh viện, công viên, đường và tự đặt thuế. Dân chỉ đến khi có việc làm. Thuế cao quá thì dân bỏ đi và thu về
lại ít hơn.

Tài liệu khác:

- [docs/huong-dan-choi.md](docs/huong-dan-choi.md): hướng dẫn chơi cho học sinh
- [docs/luat-choi-moi.md](docs/luat-choi-moi.md): luật chơi và công thức
- [PRODUCT.md](PRODUCT.md): game cho ai, để làm gì
- [DESIGN.md](DESIGN.md): quy ước giao diện

## Chạy thử trong Studio

1. Mở Roblox Studio, chọn File > Open from File > `EconCity.rbxlx`.
2. Bấm Play (F5).
3. Chọn công trình ở bảng Xây dựng bên phải rồi bấm vào ô trên bản đồ. Đường thì giữ chuột và kéo. Công trình nào
   cũng phải có đường nối về ô CỔNG. Xây xong bấm BẮT ĐẦU.

Mỗi tháng dài 20 giây. Trong Studio có thêm hai nút để thử nhanh: "Tick ngay" (sang tháng luôn) và "Bot xây mẫu"
(bot tự xây bằng số tiền đang có).

- Thử nhiều người chơi: Test > Clients and Servers, chọn 2 người, bấm Start.
- Thử màn hình điện thoại: Test > Device.

Khi game chưa publish, dữ liệu chỉ lưu tạm và mất khi tắt game (có dòng vàng "Chế độ thử"). Nếu Studio đã được bật
quyền API thì dữ liệu thử ghi vào kho có đuôi `_Studio`, không lẫn với dữ liệu thật của học sinh.

## Sửa code

Có thể sửa thẳng trong Studio, nhưng làm nhóm thì nên sửa file trong `src/` bằng VS Code và đồng bộ sang Studio bằng
Rojo:

1. Cài Rojo (`brew install rojo`) và plugin Rojo trong Studio.
2. Chạy `rojo serve` trong thư mục này, rồi bấm Connect ở plugin.
3. Sửa file `.luau`, Studio tự cập nhật.
4. Ghép lại file place: `rojo build -o EconCity.rbxlx`. Không có Rojo thì dùng
   `python3 tools/build_rbxlx.py EconCity.rbxlx`.

| Thư mục | Nằm ở đâu trong game | Có gì |
|---|---|---|
| `src/shared/` | ReplicatedStorage.EconCity | luật chơi và số liệu, server và client cùng dùng |
| `src/server/` | ServerScriptService.EconCityServer | lưu dữ liệu, lớp học, xếp hạng, quản trị |
| `src/client/` | StarterPlayerScripts.EconCityClient | giao diện, thành phố 3D, camera |
| `tests/` | | test chạy ngoài Studio |
| `prototypes/luat-moi/` | | bản JS của luật chơi, mở bằng trình duyệt |

Ba file hay sửa nhất:

- `src/shared/Config.luau`: mọi con số (giá, bảo trì, chỗ làm, thời gian, giới hạn lớp...).
- `src/shared/CityEngine.luau`: luật thành phố.
- `src/shared/GameTick.luau`: những gì xảy ra mỗi tháng.

## Test

Cần Lua 5.3 trở lên (`brew install lua`):

```
sh tests/run_all.sh
```

Lệnh này chạy test luật chơi, test server, một ván giả lập từ đầu đến cuối (cả chuột, cảm ứng, tay cầm) và bot cân
bằng có so kết quả với bản JS.

## Chỉnh cân bằng

Số liệu nằm ở hai chỗ và phải giống nhau: `src/shared/Config.luau` và `prototypes/luat-moi/engine.js`.

1. Sửa con số ở cả hai file.
2. Chạy `node prototypes/luat-moi/sim.js` để xem bảng điểm mới.
3. Chạy `lua tests/balance_sim.lua --no-compare` để xem bảng của bản Luau.
4. Thấy ổn thì chép bảng JS mới vào `STRATS` trong `tests/balance_sim.lua`, để lần sau test lại so được.

Đổi độ dài một tháng (`TICK_SECONDS`) không ảnh hưởng cân bằng.

## Giáo viên

Chủ game (hoặc chủ Group sở hữu game) luôn là giáo viên kiêm quản trị. Thêm giáo viên khác bằng một trong ba cách:

- Trong game: Lớp học > Quản trị > Thêm giáo viên, nhập tên đăng nhập Roblox.
- Thêm UserId vào `TEACHER_USER_IDS` hoặc `ADMIN_USER_IDS` trong `Config.luau`.
- Đặt `TEACHER_GROUP_ID` và `TEACHER_GROUP_MIN_RANK`: ai trong Group từ cấp đó trở lên là giáo viên.

Trong Studio ai cũng là giáo viên để dễ thử (`STUDIO_EVERYONE_IS_TEACHER`).

Game không hỏi email, mật khẩu hay tên thật. Giáo viên nhận ra học sinh qua tên hiển thị Roblox. Chat bị ẩn. Tên lớp
và kịch bản đều đi qua bộ lọc chữ của Roblox.

## Đưa game lên Roblox

1. File > Publish to Roblox.
2. Game Settings > Permissions: để Private khi còn thử với lớp.
3. Game Settings > Places > Max Players: ít nhất bằng sĩ số lớp + 1 (giáo viên). Tối đa 61, vì mỗi lớp tối đa 60 em.
   Đặt thấp hơn thì phòng học riêng đầy, học sinh vào sau không vào được.
4. Creator Dashboard: điền Maturity & Compliance Questionnaire.
5. Muốn thử lưu dữ liệu thật trong Studio: Game Settings > Security > Enable Studio Access to API Services.

Phòng học riêng, lưu dữ liệu và xếp hạng giữa các server chỉ chạy sau khi publish.

Trước khi cho học sinh chơi:

- Học sinh dưới 16 tuổi chỉ chơi được khi game vào chương trình Roblox Kids and Select. Tài khoản đăng game phải xác
  minh tuổi và danh tính, bật xác thực 2 lớp, trả phí đăng (hoặc có Roblox Plus/Premium từ 2 tháng trở lên). Game
  phải qua đánh giá an toàn: đủ 250 lượt chơi của người đã xác minh tuổi trong 60 ngày, hoặc trả 50.000 Robux để duyệt
  nhanh (được hoàn lại). Trước đó chỉ người 16+ đã xác minh tuổi mới thấy game.
- Ở Việt Nam, Roblox do VNG phát hành và chỉ chơi được game đã được cấp phép. Phải làm thủ tục với VNG trước.

## Xoá dữ liệu khi Roblox yêu cầu

Roblox gửi yêu cầu xoá dữ liệu (Right to be Forgotten) kèm UserId. Vào Quản trị > Xoá dữ liệu, nhập UserId, bấm hai
lần. Lệnh này xoá dữ liệu của người đó ở tất cả các kho sau:

| Kho | Key | Nội dung |
|---|---|---|
| `EconCity_Profiles_v1` | `u_<UserId>` | hồ sơ, ván đang chơi, lịch sử ván |
| `EconCity_Classes_v1` | `c_<MÃ>` | thành viên lớp (`members["<UserId>"]`), giáo viên của lớp |
| `EconCity_Scenarios_v1` | `t_<UserId>` | kịch bản giáo viên tự tạo |
| `EconCity_Admin_v1` | `teachers`, `bans`, `log` | danh sách giáo viên, danh sách cấm, nhật ký |
| `EconCity_LB_Global_v2`, `EconCity_LB_Class_v2_<MÃ>` (Ordered) | `<UserId>` | điểm xếp hạng |
| `EconCity_LB_Global_v1`, `EconCity_LB_Class_v1_<MÃ>` (Ordered) | `<UserId>` | điểm xếp hạng luật cũ (không ghi nữa, vẫn xoá) |
| MemoryStore `EconCity_ClassLive_v1` | `u_<UserId>` | tiến độ trực tiếp (tự hết hạn sau 2 phút) |

## Chưa làm xong

- Cân bằng mới thử bằng bot, chưa thử với học sinh thật.
- Ván đang chơi dở theo luật cũ không chơi tiếp được, vào lại sẽ bắt đầu ván mới. Lịch sử ván cũ vẫn còn.
- Phòng học riêng, MessagingService, MemoryStore, Ban API và tra tên đăng nhập mới chỉ thử bằng giả lập, chưa thử trên
  game đã publish.
- Chưa thử thành phố kín lưới trên điện thoại yếu.
