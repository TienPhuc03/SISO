import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

/// [Dev A] Màn hình Đăng nhập bằng Email Sinh viên (@hutech.edu.vn, @uef.edu.vn...)
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  //regex chuẩn kiểm tra đuôi 5 trường Bình Thạnh
  final RegExp _eduRegex = RegExp(r'^[a-zA-Z0-9._%+-]+@(hutech\.edu\.vn|uef\.edu\.vn|ut\.edu\.vn|ftu\.edu\.vn|hiu\.vn)$');

  @override
  void dispose() {
    _emailController.dispose(); //tránh rò rỉ bộ nhớ
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      //gọi lên Riverpod Provider, tự động set loading state
      ref.read(authNotifierProvider.notifier).requestOtp(_emailController.text.trim());
    }
  }

  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('SISO - Xác thực Sinh viên')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Nhập Email trường cấp để đại diện tranh tài',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 32),
              
              //Input Email với Regex Validator
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email Sinh viên',
                  hintText: 'nguyenvana@hutech.edu.vn',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.school),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Vui lòng không để trống email';
                  }
                  if (!_eduRegex.hasMatch(value.trim())) {
                    return 'SISO hiện chỉ hỗ trợ HUTECH, UEF, UT, FTU2, HIU';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              
              //xử lý trạng thái hiển thị
              if (authState.isLoading)
                const Center(child: CircularProgressIndicator())
              else
                ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Nhận mã OTP', style: TextStyle(fontSize: 16)),
                ),
                
              //hiển thị lỗi từ Backend (nếu có)
              if (authState.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  authState.error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ]
            ],
          ),
        ),
      ),
    );
  }
}
