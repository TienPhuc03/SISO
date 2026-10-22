import 'package:flutter/material.dart';

/// [Dev A] Màn hình Xác nhận OTP / Magic Link từ hộp thư trường
class VerifyScreen extends StatelessWidget {
  const VerifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Xác nhận OTP / Magic Link')),
      body: const Center(
        child: Text('Kiểm tra hộp thư sinh viên để hoàn tất xác thực'),
      ),
    );
  }
}
