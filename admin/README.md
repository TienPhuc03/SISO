# SISO Admin (web)

Web quản trị cho SISO: chống gian lận, bản đồ Lãnh thổ, thống kê, quản lý Mùa giải / Trường / Đấu trường / Sinh viên.
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

-- Hoặc nâng quyền một Sinh viên đã đăng nhập app bằng email trường
UPDATE public.users SET role = 'admin' WHERE email = '<email>';
```

Email ngoài trường chỉ đăng nhập được khi đã là admin; không ai tự đăng ký bằng email thường được.

Schema cần chạy trước: section 11 của `backend/src/database/init_schema.sql`.
