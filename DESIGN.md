# Ghi chú giao diện

Ghi lại các quy ước đang dùng trong `src/client/UI` và `src/client/City` để sửa sau này không lệch nhau.

## Màu

Tất cả nằm trong `Theme.Colors` (`src/client/UI/Theme.luau`).

| Nhóm | Token | Mã |
|---|---|---|
| Nền thẻ | `panel`, `panelAlt`, `panelHover` | #FFFFFF, #F2F5FA, #E8EEF7 |
| Viền, kẻ | `stroke`, `strokeStrong`, `rule` | #DBE2EC, #C4CEDC, #E7ECF3 |
| Bóng, lớp phủ | `shadow`, `overlay` | #0B1220, #0C1424 |
| Chữ | `text`, `textDim`, `textMuted` | #182234, #546278, #67758A |
| Nút | `accent`, `success`, `amber`, `danger`, `violet` | #2E6BFF, #22B35E, #F5A524, #E5484D, #7C5CFF |
| Trạng thái | `good`, `warn`, `bad` | #1A9E55, #C47800, #E0364A |
| Chỉ số | `gold` (ngân sách), `people` (dân số), `jobs` (việc làm), `mood` (dịch vụ) | #F5B301, #7C5CFF, #14A0C8, #F0507A |

- Nút: `success` cho START / RESUME / PLAY AGAIN, `amber` cho PAUSE, `accent` cho SELECT TO BUILD và nút chính
  trong bảng, `danger` khi xác nhận phá dỡ, `violet` cho nút bot (chỉ có trong Studio).
- Hạnh phúc lấy màu qua `Theme.happinessColor`: từ 65 trở lên xanh, 50 đến 64 cam, dưới 50 đỏ.
- Nền nhạt sau biểu tượng = màu chính pha trắng khoảng 86%.
- Màu 8 loại đất chỉ lấy từ `Config.BUILDINGS[...].color` (qua `Theme.land` / `Theme.landInk`). Ô chọn loại đất, ô
  màu của mẫu, viền lô và mái nhà trên bản đồ phải cùng một nguồn này.
- Màu đậm chỉ dùng khi có nghĩa (thao tác, trạng thái, loại đất, chỉ số), không tô cho đẹp.

## Chữ

Chỉ dùng Builder Sans (font của Roblox): `Theme.Font`, `FontMedium`, `FontBold` cho nhãn và nút,
`FontDisplay` (ExtraBold) cho tiêu đề và số lớn.

- Cỡ: tiêu đề thẻ 15-18, tiêu đề cửa sổ 21, tên game 20, số chỉ số 17-20, nội dung 12-14, nhãn 11-12.
- Viết hoa chữ đầu câu như bình thường. Chỉ nút chính viết hoa toàn bộ (START, PAUSE, RESUME, NEW GAME,
  SELECT TO BUILD, PLAY AGAIN), chữ GATE trên bản đồ và mã loại đất (RES, COM, IND...).
- Khi bật bố cục gọn, chữ tạo qua `C.label`, `C.button`, `C.textbox`, `C.pill` được nâng lên tối thiểu 13. Chữ mới nên
  tạo qua các hàm này.

## Bố cục

Khung thiết kế 1366x768. `UIScale = min(rộng/1366, cao/768)`, kẹp trong 0,6-1,15 (máy cảm ứng 0,72-1,15).

- Góc trên trái: thẻ thành phố tại (12, 10), cao 76, gồm logo 46x46, tên game, "Month m / 24" kèm thanh nhiệm kỳ và
  bốn ô chỉ số 112x60. Nhãn vai trò / chế độ thử ở y = 94. Thẻ How to play và cảnh báo rộng 300, bắt đầu từ y = 126.
- Góc trên phải: thanh điều khiển cao 60 gồm ô trạng thái + đồng hồ, nút chính 136x44, Tick now (Studio), bốn nút
  điều hướng 64x44.
- Bên phải: bảng Xây dựng rộng 340, cao tối đa 580, đặt tại y = 80 (`BuildPanel.TOP`).
- Dưới trái: dải thống kê bốn thẻ 156x62, cách nhau 8. Dưới phải: nút camera tròn 42 và nút Walk.
- Giữa: thông báo rộng 440 tại y = 96. Cửa sổ mặc định 560x440, luôn thu vừa màn hình (chừa 24).

Bố cục gọn bật khi rộng thiết kế < 1250 hoặc cao < 700: ẩn dải thống kê và Tick now, ô trạng thái chỉ còn đồng hồ,
nhãn rút ngắn (Ranking thành Rank, Hide / Build thành Build), thẻ thành phố bỏ dòng phụ.

## Thành phần

- `C.panel`: thẻ trắng bo 16 có viền bóng (`C.shadowStroke`, `shadow` dày 1,5, trong 0,86). `C.well`: ô nền nhạt bo 12.
- `C.button`: kiểu `primary | success | warning | danger | violet | secondary | white | ghost` hoặc một Color bất kỳ
  (ô màu đất). Nút cao từ 24 trở lên có gờ 3-4 px ở đáy (`C.lip`, tắt bằng `Lip = false`). Bấm: thu còn 0,95 trong
  0,06 s rồi bật lại.
- `C.pill`, `C.closeButton`, `C.tabs`, `C.slider` (thanh thuế đổi màu xanh/cam/đỏ theo mức), `C.textbox`.
- `C.popIn`, `C.fadeOut`, `C.restoreFade` cho thẻ, thông báo, băng chúc mừng.
- Bo góc: nút 12, thẻ 16-20, ô nền 12-16, viên nhãn và nút tròn bo hết (`C.round`).
- Biểu tượng vẽ bằng Frame trong `Icons.luau` (đồng xu, người, cặp, mặt cười, tim, thùng hàng, biểu đồ, bục, lưới,
  dấu tích, chạy/dừng/tua, chú ý, thông tin, cúp, bot, bản đồ). Không dùng emoji, không dùng ảnh tải lên.
- Màn kết thúc: huy chương ghi số tháng (vàng khi xong nhiệm kỳ, đỏ khi phá sản), nhãn "New record!" khi bằng điểm cao
  nhất, lưới 3x2 ô số, ba nút PLAY AGAIN / View history / View city.
- Phần trang trí (pháo giấy, viền đỏ khi phá sản) gắn thuộc tính `Decor = true` để không chặn bấm xuống bản đồ.
- Hiệu ứng ngắn, không quá 0,4 s: số nhảy khi sang tháng, thẻ bật ra, pháo giấy khi bắt đầu và khi xong nhiệm kỳ.

## Bản đồ 3D

- Khu đất của người chơi là bãi cỏ 12x12 ô (mỗi ô 14 stud), viền vỉa hè bê tông, chừa lối ở cổng (cạnh +Z).
- Mô hình công trình nằm ở `CitySpecs`: mỗi loại một hàm, mặt tiền quay về +Z. `CityRenderer` xoay cả công trình về
  phía ô đường kề bên, ưu tiên +Z, +X, -X rồi -Z vì camera nhìn từ phía +X, +Z. Đường mới làm sát bên thì nhà quay lại
  ngay, không chạy lại hiệu ứng mọc.
- Mái, mái che, biển hiệu lấy màu đất của loại công trình. Lô giữ viền màu đất để nhìn xa vẫn biết loại đất.
- Ô đường (`CitySpecs.road`): vỉa hè ở bốn góc và ở cạnh không nối, vạch tim đứt quãng; ngã ba, ngã tư có vạch qua
  đường và đèn giao thông; đoạn thẳng có đèn đường và cây.
- Phố xá xung quanh do server dựng (`World.luau`), giống nhau ở mọi server: đường vành đai, lưới phố (đường rộng 16,
  khối phố 60), đại lộ từ cổng, nhà cao tầng, công viên, sông và cầu ở phía xa.
- Camera toàn cảnh nhìn từ phía +X, +Z nên nhà sát khu đất để thấp (không quá 28) cho khỏi che và khỏi đổ bóng lên
  lưới. Nhà cao dần về phía -X, -Z.
