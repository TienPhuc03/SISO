/** Bỏ dấu tiếng Việt, chữ thường, gộp khoảng trắng: "Đại Học  Kinh tế" -> "dai hoc kinh te". Khớp foldVietnamese phía app. */
export function foldVietnamese(s: string): string {
  return s
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D')
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .trim();
}
