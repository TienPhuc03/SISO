import 'package:flutter_test/flutter_test.dart';
import 'package:siso_project/src/features/map/data/hexagon_repository.dart';

void main() {
  group('parseListPayload (đọc BaseResponseDto)', () {
    test('lấy mảng trong data khi success = true', () {
      final rows = parseListPayload({
        'success': true,
        'message': 'Lấy trạng thái ô đất thành công.',
        'data': [
          {'h3Index': '8a65b56718b7fff', 'hexColor': '#FFCC00'},
          {'h3Index': '8a65b5671d6ffff', 'hexColor': '#44FFFFFF'},
        ],
        'timestamp': '2026-11-04T10:00:00.000Z',
      });

      expect(rows.map((r) => r['h3Index']), ['8a65b56718b7fff', '8a65b5671d6ffff']);
    });

    test('success khác true thì trả rỗng', () {
      expect(parseListPayload({'success': false, 'code': 'ERR_303', 'data': []}), isEmpty);
    });

    test('thân phản hồi không phải object, hoặc data không phải mảng, thì trả rỗng', () {
      expect(parseListPayload(null), isEmpty);
      expect(parseListPayload([{'h3Index': 'x'}]), isEmpty); // định dạng cũ (mảng thô)
      expect(parseListPayload({'success': true, 'data': 'x'}), isEmpty);
    });

    test('bỏ phần tử không phải object trong data', () {
      final rows = parseListPayload({
        'success': true,
        'data': [{'h3Index': 'a'}, 'rác', 42],
      });

      expect(rows, [{'h3Index': 'a'}]);
    });
  });
}
