export function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

/**
 * Trả về domain gốc của trường (trong `domains`, tức cột `universities.email_domain`) mà email thuộc về,
 * chấp nhận cả subdomain (`a@st.hutech.edu.vn` -> `hutech.edu.vn`); không khớp thì `null`.
 * Khớp domain dài nhất trước, cùng quy tắc với trigger SQL `assign_university_id`.
 */
export function matchCampusDomain(email: string, domains: readonly string[]): string | null {
  const parts = normalizeEmail(email).split('@');
  if (parts.length !== 2 || !parts[0] || !parts[1]) return null;
  const domain = parts[1];
  return (
    [...domains]
      .sort((a, b) => b.length - a.length)
      .find((d) => domain === d || domain.endsWith(`.${d}`)) ?? null
  );
}
