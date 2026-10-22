import 'package:flutter/material.dart';

/// [Dev A] Màn hình Đăng nhập bằng Email Sinh viên (@hutech.edu.vn, @uef.edu.vn...)
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SISO - Xác thực Sinh viên')),
      body: const Center(
        child: Text('Đăng nhập bằng Email Sinh viên (@*.edu.vn)'),
      ),
    );
  }
}
