# SISO (Step In Step Out)

Trò chơi chạy bộ chiếm lãnh thổ giữa sinh viên các trường đại học; giai đoạn MVP gồm 5 trường ở Bình Thạnh, TP.HCM. Thuật ngữ chính viết bằng tiếng Việt (dùng trong báo cáo và trao đổi), kèm tên tiếng Anh dùng trong code.

## Ngôn ngữ

### Người chơi và sân chơi

**Sinh viên** (`Student`):
Người chơi SISO; luôn thuộc đúng một Trường tham gia thi đấu.
_Tránh dùng_: User, Người dùng, Runner, Vận động viên

**Trường** (`University`):
Một trường đại học tham gia thi đấu, xác định Sinh viên của mình bằng đuôi email trường cấp; ở MVP gồm HUTECH, UEF, UTH, FTU2 và HIU.
_Tránh dùng_: Campus, Phe, Đội, Khuôn viên

**Đấu trường** (`Arena`):
Một vùng mở có ranh giới cố định, nơi Sinh viên của mọi Trường được chiếm đất; có thể là một khuôn viên trường nhưng không thuộc riêng Trường nào.
_Tránh dùng_: Sân đấu, Turf, Sân chơi

**Ô đất** (`Hex`):
Một ô lục giác H3 độ phân giải 10 nằm trong Đấu trường, là đơn vị nhỏ nhất có thể bị Chiếm.
_Tránh dùng_: Lục giác, Hexagon, Cell, Turf, Lãnh thổ

**Đấu trường đang hoạt động**:
Đấu trường đang mở cho việc chiếm đất trong Mùa giải; chỉ Ô đất của các Đấu trường này được tính vào % Lãnh thổ.
_Tránh dùng_: Đấu trường mở, Arena active

### Chạy bộ

**Phiên chạy** (`Run`):
Một lần chạy của một Sinh viên, từ lúc bắt đầu đến lúc kết thúc; là Chạy khép vòng hoặc Chạy tự do.
_Tránh dùng_: Session, Lượt chạy, Chạy đánh lẻ, Chạy về quê

**Chạy khép vòng** (`Arena Loop`):
Phiên chạy trong một Đấu trường có khép được Vòng khép, vừa tác động lên Ô đất (Chiếm, Tuần tra hoặc Công phá) vừa cộng km cho Trường.
_Tránh dùng_: Chạy chiếm đất, Turf run

**Chạy tự do** (`Free Run`):
Phiên chạy ở bất kỳ đâu không khép được vòng trong Đấu trường (kể cả khi về quê); chỉ cộng km, không chiếm đất.
_Tránh dùng_: Chạy đánh lẻ, Chạy về quê, Chạy từ xa

**Vòng khép** (`Loop`):
Đường chạy khép kín của một Phiên chạy trong Đấu trường; các Ô đất nằm trên và bên trong đường đó là phần chịu tác động của Phiên chạy.
_Tránh dùng_: Vòng lặp, Chu trình, Vòng chạy, Loop closure

### Giữ đất

**Trung lập** (`Neutral`):
Trạng thái của Ô đất không thuộc Trường nào, vì chưa từng bị chiếm hoặc đã Hao mòn hết.
_Tránh dùng_: Trống, Vô chủ, Trắng

**Lãnh thổ** (`Territory`):
Tập hợp các Ô đất mà một Trường đang giữ.
_Tránh dùng_: Đất chiếm đóng, Diện tích, Turf

**Chiếm** (`Claim`):
Việc một Ô đất về tay Trường của người chạy với Độ bền 100: ngay lập tức nếu Ô đất đang Trung lập, hoặc khi Công phá làm Độ bền của nó về 0.
_Tránh dùng_: Cướp, Chinh phục, Capture

**Công phá** (`Siege`):
Tác động của một Vòng khép lên Ô đất đang thuộc Trường khác: trừ 25 Độ bền mỗi lần, và Ô đất bị Chiếm khi Độ bền về 0.
_Tránh dùng_: Tấn công, Đánh, Cướp đất, Damage

**Độ bền** (`Shield HP`):
Mức sức giữ của một Ô đất đã bị Chiếm, từ 0 đến 100; đầy 100 khi vừa Chiếm hoặc vừa Tuần tra, giảm do Hao mòn và Công phá.
_Tránh dùng_: HP, Máu, Khiên

**Tuần tra** (`Patrol`):
Tác động của một Vòng khép lên Ô đất mà Trường của người chạy đang giữ: Độ bền hồi về 100.
_Tránh dùng_: Bảo vệ đất, Gia hạn

**Hao mòn** (`Decay`):
Sự suy giảm Độ bền khi một Ô đất không được Tuần tra: sau 24 giờ còn 50, sau 48 giờ Ô đất trở về Trung lập.
_Tránh dùng_: Mất máu, Xuống cấp

### Điểm số và Mùa giải

**Mùa giải** (`Season`):
Một chu kỳ thi đấu có ngày bắt đầu và kết thúc; khi kết thúc, Lãnh thổ và Quỹ Km của mọi Trường trở về 0.
_Tránh dùng_: Season (trong văn bản tiếng Việt), Đợt, Vòng đấu

**Quỹ Km** (`Season Km`):
Tổng km hợp lệ của mọi Phiên chạy của Sinh viên một Trường trong Mùa giải hiện tại.
_Tránh dùng_: Km cống hiến, Km toàn cầu, Km đánh lẻ, Tổng km

**Km cá nhân** (`Personal Km`):
Tổng km hợp lệ của một Sinh viên trong Mùa giải hiện tại; về 0 khi sang Mùa giải mới.
_Tránh dùng_: Km của tôi, Thành tích cá nhân

**% Lãnh thổ** (`Territory %`):
Số Ô đất trong Lãnh thổ của một Trường chia cho tổng số Ô đất của mọi Đấu trường đang hoạt động.
_Tránh dùng_: % Đất, Tỷ lệ đất

**% Km** (`Mileage %`):
Quỹ Km của một Trường chia cho tổng Quỹ Km của mọi Trường tham gia thi đấu.
_Tránh dùng_: % Km toàn cầu, % Cống hiến

**Sức mạnh Tổng hợp** (`Composite Power`):
Thước đo xếp hạng Trường, bằng một nửa % Lãnh thổ cộng một nửa % Km.
_Tránh dùng_: Điểm Tổng lực, Điểm Sức mạnh Tổng hợp, Tổng điểm, Điểm mùa

**Quán quân** (`Champion`):
Trường có Sức mạnh Tổng hợp cao nhất lúc Mùa giải kết thúc.
_Tránh dùng_: Vô địch, Nhà vô địch

**Đại sảnh Danh vọng** (`Hall of Fame`):
Danh sách Quán quân của các Mùa giải đã qua.
_Tránh dùng_: Bảng vàng, Bảng vinh danh

### Chống gian lận

**Anti-GIGO**:
Toàn bộ cơ chế phía server quyết định một Phiên chạy có hợp lệ hay không, gồm bốn Cổng kiểm định nối tiếp.
_Tránh dùng_: Bộ lọc, Lớp phòng thủ, Tường lửa, Chống hack

**Phiên bị loại** (`Rejected Run`):
Phiên chạy không qua Anti-GIGO; không được cộng km hay tác động lên Ô đất, và mang một mã lỗi.
_Tránh dùng_: Phiên lỗi, Phiên gian lận, Phiên huỷ

**Cổng Danh tính** (`Identity Gate`):
Cổng kiểm định tầng 0: chỉ Sinh viên đăng nhập bằng email của một Trường tham gia thi đấu mới được chơi.
_Tránh dùng_: Tầng xác thực, Đăng nhập

**Cổng Động học** (`Kinematic Gate`):
Cổng kiểm định tầng 1: loại Phiên chạy có tốc độ vượt sức người, sai số định vị quá lớn hoặc định vị giả.
_Tránh dùng_: Bộ lọc Kalman, Tầng GPS

**Cổng Sinh trắc** (`Biometric Gate`):
Cổng kiểm định tầng 2: loại Phiên chạy có nhịp bước chân không khớp với tốc độ, như khi đi xe máy.
_Tránh dùng_: Bộ lọc FFT, Tầng IMU, Chống xe máy

**Nhịp bước** (`Cadence`):
Số bước chân mỗi phút (SPM) của Sinh viên trong Phiên chạy; là căn cứ để Cổng Sinh trắc phân biệt chạy bộ với đi xe máy.
_Tránh dùng_: Tần số bước, Cadence (trong văn bản tiếng Việt)

**Cổng Hình học** (`Topology Gate`):
Cổng kiểm định tầng 3: chỉ chấp nhận Vòng khép hợp lệ và không vượt giới hạn số Ô đất cho phép.
_Tránh dùng_: Flood Fill, Tầng H3
