import { BadRequestException } from '@nestjs/common';
import * as h3 from 'h3-js';
import { H3Service } from './h3.service';

describe('H3Service (Topology Gate Unit Tests)', () => {
  let service: H3Service;

  beforeEach(() => {
    service = new H3Service();
  });

  it('phải ném ra lỗi ERR_301 nếu chu trình đường biên vượt quá 150 ô H3', () => {
    const fakeHexes = Array.from({ length: 151 }, (_, i) => `hex_${i}`);
    expect(() => service.calculateEnclosedHexes(fakeHexes)).toThrow();
  });

  it('phải trả về mảng rỗng nếu đầu vào rỗng', () => {
    const res = service.calculateEnclosedHexes([]);
    expect(res).toEqual([]);
  });

  it('từ chối chuỗi không phải ô H3, không trả nguyên chuỗi rác để ghi vào DB', () => {
    const valid = h3.latLngToCell(10.8, 106.718, 10);
    expect(() => service.calculateEnclosedHexes([valid, 'not_a_hex', valid])).toThrow(BadRequestException);
  });

  it('từ chối ô H3 sai độ phân giải (không phải res 10)', () => {
    const res9 = h3.latLngToCell(10.8, 106.718, 9);
    expect(() => service.calculateEnclosedHexes([res9])).toThrow(BadRequestException);
  });

  it('vẫn nhận ô res 10 hợp lệ', () => {
    const valid = h3.latLngToCell(10.8, 106.718, 10);
    expect(service.calculateEnclosedHexes([valid])).toEqual([valid]);
  });

  describe('khép vòng với đa giác thật (vòng k=3 quanh HUTECH: 18 ô biên, 19 ô bên trong)', () => {
    const center = h3.latLngToCell(10.8016, 106.7146, 10);
    const ring = h3.gridRingUnsafe(center, 3);
    const inner = h3.gridDisk(center, 2);

    it('chiếm đủ toàn bộ ô bên trong cùng ô biên', () => {
      const res = service.calculateEnclosedHexes(ring);

      expect(ring).toHaveLength(18);
      expect(res).toEqual(expect.arrayContaining([...ring, ...inner]));
      expect(res).toHaveLength(37);
    });

    it('chạy ngược chiều, lặp ô đầu ở cuối, đứng lâu trong một ô: cùng kết quả', () => {
      const messy = [...ring].reverse().flatMap((hex, i) => (i === 4 ? [hex, hex, hex] : [hex]));
      messy.push(messy[0]);

      expect(new Set(service.calculateEnclosedHexes(messy))).toEqual(new Set([...ring, ...inner]));
    });

    it('ô biên sai thứ tự đường chạy: ERR_302, không âm thầm chiếm thiếu', () => {
      const shuffled = [0, 9, 3, 12, 6, 15, 1, 10, 4, 13, 7, 16, 2, 11, 5, 14, 8, 17].map((i) => ring[i]);

      expect(() => service.calculateEnclosedHexes(shuffled)).toThrow(
        expect.objectContaining({ response: expect.objectContaining({ code: 'ERR_302' }) }),
      );
    });

    it('đường hình số 8 (đi lại một ô cũ giữa vòng): ERR_302', () => {
      const other = h3.gridRingUnsafe(ring[0], 1).filter((hex) => !ring.includes(hex));
      const figure8 = [...ring, ring[0], ...other];

      expect(() => service.calculateEnclosedHexes(figure8)).toThrow(
        expect.objectContaining({ response: expect.objectContaining({ code: 'ERR_302' }) }),
      );
    });

    it('vòng k=7 (42 ô biên nhưng 169 ô tổng): ERR_301', () => {
      expect(() => service.calculateEnclosedHexes(h3.gridRingUnsafe(center, 7))).toThrow(
        expect.objectContaining({ response: expect.objectContaining({ code: 'ERR_301' }) }),
      );
    });
  });
});
