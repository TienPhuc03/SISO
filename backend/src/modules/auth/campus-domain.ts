/**
 * Đuôi email của 5 trường Bình Thạnh. Phải khớp với cột `email_domain` của
 * bảng `universities` và với `AppConstants.allowedCampusDomains` bên Flutter.
 */
export const CAMPUS_DOMAINS = [
  'hutech.edu.vn',
  'uef.edu.vn',
  'ut.edu.vn',
  'ftu.edu.vn',
  'hiu.vn',
] as const;

export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

/**
 * Trả về domain gốc của trường nếu email thuộc 5 trường (chấp nhận cả subdomain,
 * ví dụ `a@st.hutech.edu.vn` -> `hutech.edu.vn`), ngược lại trả `null`.
 * Cùng quy tắc với trigger SQL `handle_new_student_user`.
 */
export function matchCampusDomain(email: string): string | null {
  const parts = normalizeEmail(email).split('@');
  if (parts.length !== 2 || !parts[0] || !parts[1]) return null;
  const domain = parts[1];
  return (
    CAMPUS_DOMAINS.find((d) => domain === d || domain.endsWith(`.${d}`)) ?? null
  );
}
