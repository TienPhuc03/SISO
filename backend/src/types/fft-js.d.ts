// Khai báo kiểu tối thiểu cho fft-js 0.0.4 (thư viện không kèm type).
declare module 'fft-js' {
  /** Số phức dạng [phần thực, phần ảo]. */
  export type Complex = [number, number];

  /** FFT Cooley-Tukey; độ dài đầu vào phải là luỹ thừa của 2. */
  export function fft(signal: number[] | Complex[]): Complex[];
}
