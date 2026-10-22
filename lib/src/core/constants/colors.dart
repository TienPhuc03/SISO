import 'package:flutter/material.dart';

/// Bảng màu nhận diện 5 trường Đại học khu vực Bình Thạnh (SRS Mục 1.1)
class CampusColors {
  CampusColors._();

  // 1. HUTECH (ĐH Công Nghệ TP.HCM) - @hutech.edu.vn
  static const Color hutechPrimary = Color(0xFFFFCC00);
  static const Color hutechSecondary = Color(0xFF003399);

  // 2. UEF (ĐH Kinh Tế - Tài Chính TP.HCM) - @uef.edu.vn
  static const Color uefPrimary = Color(0xFFED1C24);
  static const Color uefSecondary = Color(0xFFFFFFFF);

  // 3. UTH (ĐH Giao Thông Vận Tải TP.HCM) - @ut.edu.vn
  static const Color uthPrimary = Color(0xFF002B49);

  // 4. FTU2 (ĐH Ngoại Thương Cơ sở II) - @ftu.edu.vn
  static const Color ftu2Primary = Color(0xFF8A0000);

  // 5. HIU (ĐH Quốc Tế Hồng Bàng) - @hiu.vn
  static const Color hiuPrimary = Color(0xFFD81B26);

  // Màu mặc định cho ô đất trung lập (chưa có trường chiếm)
  static const Color neutralHex = Color(0x44FFFFFF);
}
