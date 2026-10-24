# Luật chơi Econ City: bản xây thành phố trên lưới (đã chốt)

Dựa trên `Proposal Econ City.docx`. Giữ khung của đề xuất (8 loại công trình, lưới, đường, thuế, công thức
việc làm/hạnh phúc), vá các chỗ thiếu và mâu thuẫn. Mọi con số đã chạy thử bằng
[prototypes/luat-moi/sim.js](../prototypes/luat-moi/sim.js) (mục 10). Bản chơi thử:
[prototypes/luat-moi/index.html](../prototypes/luat-moi/index.html) (mở thẳng trong trình duyệt), luật nằm ở
[engine.js](../prototypes/luat-moi/engine.js), kiểm tra bằng `node prototypes/luat-moi/check.js`.
Game Roblox (`src/`, bản 0.2) dùng đúng luật này; `tests/balance_sim.lua` so từng con số của bản Luau với bản JS.

## 1. Đổi gì so với đề xuất, vì sao

| # | Đề xuất | Chốt | Vì sao |
|---|---|---|---|
| 1 | Hạnh phúc H chỉ để hiển thị | H quyết định **dân đến hay bỏ đi** (mục 4, bước 3) | Nếu H không tác động gì thì thuế 100% luôn có lợi nhất, còn bệnh viện/trường/công viên chỉ tốn tiền |
| 2 | H = 0.35E + 0.15(100 - T) + 0.50S, thuế 0-100% | **H = 0.35E + 0.45(100 - 2T) + 0.20S**, thuế 0-50% | Với trọng số 0.15 thì thuế 100% mà H vẫn có thể đạt 85, tức thuế gần như không bị phạt |
| 3 | Dân số = Σ sức chứa | Dân **đến vì có việc làm**: dân mục tiêu = việc làm × độ hấp dẫn, tối đa bằng sức chứa | Nếu dân lấp nhà theo tỉ lệ H thì chỉ cần xây thừa nhà (rẻ) là bù được thuế cao |
| 4 | Không có dân thì E = 0% | Không có dân thì E = 100% (không ai thất nghiệp); giao diện hiện "—" | Nếu E = 0 thì thành phố mới có H thấp và không bao giờ có người đến |
| 5 | S = min(100, 10·BV + 5·CV + 10·Tr) | Giữ số điểm 10/5/10, nhưng S = **% dân được phục vụ**, mỗi điểm phục vụ 20 dân | Theo đề xuất thì 10 bệnh viện cho S tối đa dù thành phố có 10 hay 10.000 dân |
| 6 | Chia công nhân ngẫu nhiên | Chia **đều theo tỉ lệ**: mọi nơi thiếu người như nhau | Kết quả ổn định, học sinh hiểu được, test được |
| 7 | "Nhà máy cung cấp hàng cho shop" nhưng không có công thức | Có công thức hàng hoá G (mục 4, bước 5) | Để shop, nhà máy, văn phòng thật sự khác nhau |
| 8 | "Nối đường" chưa định nghĩa | Phải nối liền tới **ô cổng** ở mép bản đồ | Nếu chỉ cần cạnh một ô đường thì đường mất ý nghĩa |
| 9 | Σ sức chứa / Σ chỗ làm tính cả công trình chưa nối | Chỉ tính công trình **đã nối** | Đề xuất tự mâu thuẫn với câu "mọi công trình phải nối đường mới hoạt động" |
| 10 | Chưa có thời lượng, thắng/thua, phá dỡ, điểm, sự kiện | Đã có (mục 5-8) | |

## 2. Bản đồ và đường

- Lưới **12 × 12**. Mẫu chuẩn và mẫu nhỏ chiếm **1 ô**, mẫu lớn chiếm **2 × 2 ô** (mục 3), không xoay.
  Mẫu 2×2 đặt bằng ô góc trên-trái, vùng mở sang phải và xuống dưới, phải nằm trọn trong lưới và cả 4 ô phải trống.
- **Ô cổng**: một ô đường đặt sẵn ở giữa cạnh dưới (cột 6, hàng 12). Không phá được.
- **Ô đường nối** = ô đường đi được tới ô cổng qua các ô đường kề nhau (trên/dưới/trái/phải, không tính chéo).
- **Công trình đã nối** = có ít nhất một ô kề (4 hướng) là ô đường nối. Với mẫu 2×2: chỉ cần một trong 4 ô của nó có ô kề như vậy.
- Công trình chưa nối: không có dân ở, không tuyển người, không có doanh thu, không có điểm dịch vụ, **vẫn tốn bảo trì**.

## 3. Công trình

Công trình được làm khá lớn (nhà 40 người, mỗi nơi làm 20-30 chỗ) để mỗi ván chỉ cần đặt khoảng 90 công trình.

| Loại | Giá xây | Bảo trì/tháng | Chỗ làm | Doanh thu / người làm / tháng | Sức chứa | Điểm dịch vụ |
|---|---|---|---|---|---|---|
| Nhà | $600 | $10 | - | - | 40 | - |
| Shop | $1.600 | $60 | 20 | $105 (cần hàng, xem G) | - | - |
| Nhà máy | $1.200 | $80 | 30 | $55 | - | - |
| Văn phòng | $3.000 | $100 | 20 | $160 | - | - |
| Bệnh viện | $2.400 | $120 | 20 | $0 | - | 10 |
| Trường học | $2.000 | $100 | 20 | $0 | - | 10 |
| Công viên | $1.800 | $100 | - | - | - | 5 |
| Đường | $50 | $0 | - | - | - | - |

Mỗi loại có vai trò riêng:
- **Shop**: doanh thu mỗi người khá, nhưng không có hàng từ nhà máy thì không bán được gì.
- **Nhà máy**: rẻ, nhiều chỗ làm, doanh thu mỗi người thấp, cấp hàng cho shop.
- **Văn phòng**: đắt, doanh thu mỗi người cao nhất, không phụ thuộc ai, tốn ít ô đất nhất trên mỗi đồng doanh thu. Lợi về cuối ván khi lưới gần đầy.
- **Bệnh viện, trường** vừa cho điểm dịch vụ vừa tạo việc làm.
- **Công viên** không cần người làm.

### Mẫu công trình

Mỗi loại đất có mẫu chuẩn (bảng trên), một mẫu nhỏ 1×1 và (trừ y tế, đường) một mẫu lớn 2×2. Mẫu được tính đúng như
loại của nó: chung cư là nhà, siêu thị là shop (cần hàng), trạm y tế là bệnh viện...

| Mẫu | Loại | Ô | Giá xây | Bảo trì/tháng | Chỗ làm | Doanh thu / người / tháng | Sức chứa | Điểm dịch vụ |
|---|---|---|---|---|---|---|---|---|
| Nhà nhỏ | Nhà | 1 | $350 | $6 | - | - | 20 | - |
| Chung cư | Nhà | 2×2 | $3.000 | $60 | - | - | 200 | - |
| Quán cà phê | Shop | 1 | $900 | $35 | 10 | $100 | - | - |
| Siêu thị | Shop | 2×2 | $7.000 | $260 | 90 | $110 | - | - |
| Xưởng nhỏ | Nhà máy | 1 | $700 | $45 | 15 | $55 | - | - |
| Nhà máy lớn | Nhà máy | 2×2 | $5.000 | $320 | 130 | $58 | - | - |
| Văn phòng nhỏ | Văn phòng | 1 | $1.500 | $55 | 10 | $155 | - | - |
| Tháp văn phòng | Văn phòng | 2×2 | $14.000 | $420 | 90 | $170 | - | - |
| Trạm y tế | Bệnh viện | 1 | $1.200 | $60 | 8 | $0 | - | 5 |
| Trường lớn | Trường học | 2×2 | $7.000 | $350 | 80 | $0 | - | 40 |
| Công viên lớn | Công viên | 2×2 | $6.000 | $360 | - | - | - | 22 |

Cân bằng mẫu (kiểm bằng `tests/engine_spec.lua` và `tests/balance_sim.lua`):
- **Mẫu nhỏ** rẻ, hợp đầu ván ít tiền, nhưng lãi mỗi ô thấp hơn mẫu chuẩn. Bot chỉ dùng mẫu nhỏ đạt 1.336 điểm, bot mẫu chuẩn 2.155.
- **Mẫu lớn** đắt, lãi (hoặc sức chứa, điểm dịch vụ trên bảo trì) mỗi ô cao hơn mẫu chuẩn **10-30%**: phần thưởng khi lưới đã chật,
  không đủ lớn để chỉ xây mẫu lớn là thắng.
- Bản thử JS (`prototypes/luat-moi/`) và bảng mục 10 chỉ dùng mẫu chuẩn; bản Luau vẫn khớp từng con số với bản JS ở các mẫu đó.
- Bot của nút "Xây mẫu" chỉ xây mẫu lớn khi thành phố đã có dân và mua xong vẫn còn ít nhất bằng giá mẫu đó: đạt 2.235 điểm
  (mẫu chuẩn 2.155). Thử cho bot mua mẫu lớn ngay khi đủ tiền thì nó mua chung cư + công viên lớn từ tháng 0, không còn
  tiền xây chỗ làm và phá sản ở tháng 14; cho mua khi đã có lãi thì chỉ đạt 1.587 vì thừa chỗ ở, thừa dịch vụ. Bài học
  cho người chơi: mẫu lớn là món của giữa và cuối ván, khi đã dư tiền và lưới bắt đầu chật.

## 4. Một tháng diễn ra thế nào

Mỗi tháng = 1 lượt, 20 giây (giữ `TICK_SECONDS` hiện tại). Các bước tính theo đúng thứ tự:

1. **Nối đường**: loang từ ô cổng, đánh dấu công trình đã nối.
2. **Sức chứa và việc làm** (chỉ tính công trình đã nối):
   `C = Σ sức chứa nhà`, `J = Σ chỗ làm (shop, nhà máy, văn phòng, bệnh viện, trường)`.
3. **Dân đến/đi**, dùng H của **tháng trước**:
   ```
   P = min(P, C)                                         // nhà bị phá/mất nối thì dân phải đi ngay
   hấp_dẫn = 1.2 × clamp((H_trước - 50) / 25, 0, 1)      // H ≤ 50: không ai muốn ở; H ≥ 75: tối đa
   P_mục_tiêu = min(C, floor(J × hấp_dẫn))
   P đi một nửa quãng tới P_mục_tiêu mỗi tháng (làm tròn lên, để luôn tới đích)
   ```
   Hệ số 1.2 nghĩa là thành phố rất hấp dẫn sẽ có người tới nhiều hơn số việc làm, sinh ra thất nghiệp và kéo H xuống. Vòng này tự cân bằng.
4. **Việc làm**: `có_việc = min(P, J)`, `f = có_việc / J` (0 nếu J = 0). Mọi công trình có người làm đều có tỉ lệ người làm bằng nhau là f.
   `E = có_việc / P × 100` (P = 0 thì E = 100).
5. **Hàng hoá**: `G = min(1, Σ chỗ làm nhà máy / Σ chỗ làm shop)` (không có shop thì G = 1).
   Nghĩa là 1 công nhân nhà máy làm ra hàng cho 1 nhân viên shop.
6. **Doanh thu cơ bản**:
   `R = f × (Σ chỗ làm shop × 105 × G + Σ chỗ làm nhà máy × 55 + Σ chỗ làm văn phòng × 160)`
7. **Ngân sách**: `thuế_thu = R × T / 100`, `bảo_trì = Σ bảo trì MỌI công trình (kể cả chưa nối)`,
   `ngân_sách += thuế_thu - bảo_trì`.
8. **Dịch vụ**: `điểm = 10 × bệnh viện + 10 × trường + 5 × công viên` (chỉ tính công trình đã nối, không phụ thuộc số người làm).
   `S = min(100, điểm × 20 / P × 100)` (P = 0 thì S = 100). Ví dụ: 400 dân, 1 bệnh viện + 1 công viên = 15 điểm, phục vụ 300 người, nên S = 75.
9. **Hạnh phúc**: `H = clamp(0.35E + 0.45(100 - 2T) + 0.20S + phạt_sự_kiện, 0, 100)`. Lưu lại làm `H_trước` cho tháng sau.
10. **Cảnh báo, lịch sử, điểm, thắng/thua** (mục 6-9).

**Ví dụ bài học về thuế (đường cong Laffer):** E = 100 và S = 75.
- Thuế 30% thì H = 35 + 18 + 15 = 68, hấp dẫn 0,86.
- Thuế 40% thì H = 59, hấp dẫn 0,43: một nửa số người làm bỏ đi, nên thu thuế **giảm** dù thuế suất tăng.

## 5. Thao tác của người chơi

- **Ván mới**: tháng 0, ngân sách $10.000, thuế 20%, lưới trống trừ ô cổng, **đang tạm dừng**. Người chơi xây trước rồi bấm Chạy.
  H ban đầu tính với P = 0: 35 + 27 + 20 = 82.
- **Xây**: chỉ trên ô trống (mẫu 2×2: cả 4 ô trống, nằm trọn trong lưới), khi ngân sách ≥ giá. Trừ tiền ngay, có tác dụng từ lượt tính kế tiếp. Xây được cả khi đang chạy lẫn tạm dừng, không xây được khi ván đã kết thúc.
- **Kéo đường**: một lần kéo gửi một yêu cầu, tối đa 24 ô. Bỏ qua ô đã là đường. Nếu gặp ô có công trình hoặc không đủ tiền cho cả đoạn thì **từ chối cả đoạn**. Lý do: giới hạn tần suất hiện tại chỉ cho dồn 8 yêu cầu.
- **Phá dỡ**: mọi thứ trừ ô cổng, hoàn **50% giá xây**. Bấm vào ô nào của công trình 2×2 cũng phá cả công trình.
  Phá đường có thể làm công trình khác mất nối. Có hai cách: công cụ Phá dỡ (PD), hoặc nút PHÁ DỠ trong thẻ thông tin của
  công trình (bấm hai lần mới phá).
- **Thẻ thông tin**: nút "i" cạnh mỗi mẫu ở bảng Xây dựng mở thẻ có hình 3D, giá, diện tích, chỗ ở/chỗ làm, doanh thu mỗi người,
  điểm dịch vụ, bảo trì và nút CHỌN ĐỂ XÂY. Bấm vào công trình đã xây (khi không chọn công cụ) mở thẻ tình trạng của nó.
- **Đi dạo**: vẫn xây được khi đi trong thành phố. Trên màn hình cảm ứng, vuốt là xoay camera nên chỉ chạm nhẹ mới xây.
- **Thuế**: 0-50%, bước 1%. Đổi lúc nào cũng được, áp dụng từ lượt tính kế tiếp.
- Server kiểm tra lại mọi thứ: loại công trình hợp lệ, toạ độ là số nguyên trong lưới, ô trống, đủ tiền, ván chưa kết thúc.

## 6. Thắng, thua, điểm

- Một ván **24 tháng**, khoảng 8 phút nếu không tạm dừng.
- **Thua**: ngân sách < -$5.000 (giữ `FAIL_BUDGET`). Ngân sách được âm vì bảo trì, nhưng lúc âm thì không xây được gì. Bỏ luật thua khi dân < 30, vì đầu ván dân = 0.
- **Thắng**: hết 24 tháng mà chưa thua.
- **Điểm** (bảng xếp hạng, giữ điểm cao nhất): `điểm = max(0, round(có_việc × H / 100 + ngân_sách / 100))`.
  Ý nghĩa: số người dân vừa có việc vừa hạnh phúc, cộng thêm sức khoẻ tài chính. Xây thừa nhà để có dân thất nghiệp không ăn điểm.

## 7. Cảnh báo (chỉ thông báo, không gây thua)

| Mã | Điều kiện | Ý nghĩa cho người chơi |
|---|---|---|
| `BUDGET` | ngân sách < 0 | Đang lỗ, không xây được |
| `HAPPINESS` | H < 50 | Không ai muốn chuyển đến |
| `UNEMPLOYMENT` | P > 0 và E < 80 | Thiếu việc làm |
| `SHORTAGE` | có shop và G < 0,7 | Shop thiếu hàng, cần thêm nhà máy |

## 8. Sự kiện của giáo viên

Thay 11 hiệu ứng cũ (gắn với nhóm dân và cấp hạ tầng, không còn ý nghĩa) bằng 6 hiệu ứng mới. Đây cũng là bộ hiệu ứng cho kịch bản tuỳ chỉnh.

| Hiệu ứng | Tác động lên | Khoảng (bước) | Gộp khi nhiều sự kiện cùng lúc |
|---|---|---|---|
| Hệ số doanh thu | R ở bước 6 | 0,5-1 (0,05) | nhân |
| Hệ số bảo trì | bảo trì ở bước 7 | 1-2 (0,1) | nhân |
| Hệ số giá xây | giá khi xây | 1-2 (0,1) | nhân |
| Hệ số hàng hoá | cung nhà máy ở bước 5 | 0,2-1 (0,1) | nhân |
| Phạt hạnh phúc | H ở bước 9 | -30 đến 0 (1) | cộng |
| Dân bỏ đi mỗi tháng | P sau bước 3: `P -= round(P × tỉ lệ)` | 0-5% (0,5%) | lấy lớn nhất |

4 sự kiện có sẵn (đã chạy thử, xem mục 10):

| Sự kiện | Hiệu ứng | Số tháng |
|---|---|---|
| Suy thoái kinh tế | doanh thu × 0,7 | 4 |
| Đứt gãy chuỗi cung ứng | hàng hoá × 0,5 | 4 |
| Đại dịch | dân bỏ đi 2%/tháng, hạnh phúc -10 | 6 |
| Bão giá vật liệu | giá xây × 1,5, bảo trì × 1,3 | 5 |

## 9. Lịch sử và báo cáo lớp

Mỗi tháng lưu: tháng, ngân sách, **doanh thu cơ bản R** (thay GDP), hạnh phúc, **tỉ lệ việc làm E** (thay lạm phát), dân số.
CSV của lớp và biểu đồ lịch sử dùng đúng 6 cột này.

Gợi ý khi code: giữ tên trường `gdp` cho R thì ClassroomService, CSV và biểu đồ ít phải sửa. Bảng xếp hạng phải sang kho mới (`_v2`), vì điểm cũ không so được với điểm mới.

## 10. Bằng chứng chạy thử

Chạy bằng `node prototypes/luat-moi/sim.js`. Các bot chơi qua đúng `engine.js` trên lưới thật: trục đường dọc từ cổng và 4 hàng đường ngang, tức 89 ô công trình và 55 ô đường. Mỗi bot giữ một chiến thuật và một mức thuế cố định suốt 24 tháng. Bảng dưới là điểm cuối ván (F24 = phá sản ở tháng 24):

| Chiến thuật | 10% | 20% | 25% | **30%** | 35% | 40% | 50% |
|---|---|---|---|---|---|---|---|
| Cân bằng (shop + nhà máy + văn phòng, S ≥ 60) | 157 | 905 | 1789 | **2155** | 2078 | 1582 | 76 |
| Chỉ văn phòng | 116 | 738 | 1558 | **2373** | 2236 | 1131 | 67 |
| Shop + nhà máy | 171 | 943 | 1811 | **2043** | 1963 | 1535 | 76 |
| Chỉ nhà máy | 162 | 739 | 1244 | **1412** | 1330 | 983 | 70 |
| Chỉ shop (không nhà máy) | F24 | F24 | F24 | F24 | F24 | F24 | F24 |
| Không xây dịch vụ công | 204 | 182 | 99 | 25 | 20 | 9 | 0 |
| Dịch vụ cao (S ≥ 90) | 153 | 798 | 1659 | **2576** | 2277 | 1254 | 66 |
| Thừa nhà (sức chứa = 2× việc làm) | 135 | 614 | 1245 | 1517 | 1423 | 981 | 55 |

Kết luận rút ra:
- **Thuế tối ưu khoảng 30%.** Thuế thấp hơn 15% thì thiếu tiền để phát triển. Thuế từ 40% trở lên thì dân bỏ đi.
- **Không có loại công trình nào áp đảo.** Văn phòng, shop + nhà máy và chiến thuật cân bằng ngang ngửa nhau. Chỉ xây shop thì phá sản.
- **Dịch vụ công đáng tiền.** Bỏ dịch vụ công thì gần như không có dân. Đầu tư dịch vụ mạnh cho điểm cao nhất.
- **Xây thừa nhà không còn là mẹo.**
- 3.000 chiến thuật ngẫu nhiên (trộn tỉ lệ công trình, loại dịch vụ, thuế): 6 chiến thuật tốt nhất đều trộn đủ 3 loại việc làm, dùng đủ bệnh viện/trường/công viên, thuế 28-39%. 67/3.000 phá sản.
- Bản đầu của mô phỏng giả định mỗi công trình tốn nửa ô đường. Chạy trên lưới thật thì điểm lệch dưới 5% và mọi kết luận giữ nguyên.
- **Sự kiện** (gán cho bot cân bằng ở tháng 6 hoặc 12, thuế 25-30%): điểm giảm 8-12% với đứt gãy chuỗi cung ứng, 13-18% với suy thoái, 17-22% với bão giá, 24-28% với đại dịch. Không bot nào phá sản.

## 11. Còn cần người chơi thật thử (trên bản prototype)

- Với chiến thuật cân bằng ở thuế 30%, lưới đầy khoảng **tháng 20**, 4 tháng cuối chỉ còn chỉnh thuế. Nếu thấy chán thì nới lưới lên 13×13 hoặc giảm doanh thu khoảng 10%.
- Mức hoàn tiền khi phá dỡ và cảm giác đầu ván ở thuế mặc định 20%: bot không cảm nhận được những thứ này.
- Số thao tác mỗi ván (khoảng 90 công trình + kéo đường) cần thử với học sinh thật, nhất là trên điện thoại và tay cầm.
