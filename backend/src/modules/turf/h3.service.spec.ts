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
});
