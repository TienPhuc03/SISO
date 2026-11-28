# SISO Admin (web)

Web quản trị cho SISO: chống gian lận, bản đồ Lãnh thổ, thống kê, quản lý Mùa giải / Trường (duyệt, gộp Trường Sinh viên tự thêm) / Đấu trường / Sinh viên, Quán quân theo Cụm, xử lý báo cáo Diễn đàn.
Vite + React + TypeScript, Tailwind v4 + shadcn/ui, TanStack Query/Table, Recharts, MapLibre + h3-js, socket.io-client.

## Chạy

```bash
cp .env.example .env   # VITE_API_BASE_URL trỏ tới backend (mặc định http://localhost:3000)
npm install
npm run dev            # http://localhost:5173
```

## Quyền admin

Đăng nhập bằng email + OTP. Chỉ tài khoản có `users.role = 'admin'` vào được; cấp quyền bằng SQL trong Supabase SQL Editor:

```sql
-- Email thường (gmail...): tạo sẵn tài khoản admin, không thuộc Trường nào
INSERT INTO public.users (email, display_name, role) VALUES (lower('<email>'), 'Admin', 'admin')
ON CONFLICT (email) DO UPDATE SET role = 'admin';

-- Hoặc nâng quyền một tài khoản đã đăng nhập app
UPDATE public.users SET role = 'admin' WHERE email = '<email>';
```

Ai cũng đăng nhập được bằng email bất kỳ (OTP) hoặc Google, nhưng chỉ tài khoản `role = 'admin'` mới vào được trang admin (còn lại bị ERR_107).

Schema cần chạy trước: section 6C (Cụm, quận, Trường theo cơ sở), 11 (admin) và 12 (Diễn đàn) của `backend/src/database/init_schema.sql`.
