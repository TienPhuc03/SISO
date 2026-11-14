import { Injectable, BadRequestException } from '@nestjs/common';
import * as h3 from 'h3-js';

/** Độ phân giải H3 dùng thống nhất ở client và server. */
export const H3_RESOLUTION = 10;

type Point = [number, number];

@Injectable()
export class H3Service {
  private readonly MAX_HEX_PER_LOOP = 150; // Giới hạn an toàn chống lạm dụng (ERR_301)

  /**
   * Tính toán tập hợp các ô lục giác nằm trong chu trình khép kín (Flood Fill / Polygon to Cells).
   * `boundaryIndexes` phải theo đúng thứ tự đi qua trên đường chạy; ô đầu lặp lại ở cuối thì được bỏ qua.
   */
  calculateEnclosedHexes(boundaryIndexes: string[]): string[] {
    if (!boundaryIndexes || boundaryIndexes.length === 0) {
      return [];
    }

    // 1. Kiểm tra giới hạn an toàn đường biên
    if (boundaryIndexes.length > this.MAX_HEX_PER_LOOP) {
      throw new BadRequestException({
        code: 'ERR_301',
        message: `LOOP_TOO_LARGE: Vòng chạy ${boundaryIndexes.length} ô vượt ngưỡng an toàn 150 ô H3.`,
      });
    }

    // Chỉ nhận ô H3 hợp lệ ở res 10: chuỗi rác (hoặc ô sai độ phân giải) không được ghi vào h3_hexagons.
    const invalid = boundaryIndexes.find(
      (hex) => typeof hex !== 'string' || !h3.isValidCell(hex) || h3.getResolution(hex) !== H3_RESOLUTION,
    );
    if (invalid !== undefined) {
      throw new BadRequestException(
        `INVALID_H3_INDEX: "${String(invalid)}" không phải ô H3 res ${H3_RESOLUTION} hợp lệ.`,
      );
    }

    // 2. Bỏ ô trùng liên tiếp (đứng lâu trong một ô) và ô đầu lặp lại ở cuối vòng.
    const ring = boundaryIndexes.filter((hex, i) => hex !== boundaryIndexes[i - 1]);
    if (ring.length > 1 && ring[0] === ring[ring.length - 1]) ring.pop();

    // Vòng phải khép: ô cuối liền kề ô đầu (~ngưỡng khép vòng 20 m), không để server tự nối một đường thẳng dài.
    if (ring.length > 1 && !h3.areNeighborCells(ring[0], ring[ring.length - 1])) {
      throw new BadRequestException({
        code: 'ERR_302',
        message: 'LOOP_NOT_CLOSED: Ô cuối của đường biên không liền kề ô đầu, vòng chạy chưa khép.',
      });
    }

    if (ring.length < 3) {
      return Array.from(new Set(ring));
    }

    // 3. Tâm các ô đường biên thành đa giác, dạng [lat, lng] (polygonToCells với isGeoJson = false).
    const coordinates = ring.map((hex) => h3.cellToLatLng(hex) as Point);
    if (new Set(ring).size !== ring.length || this.selfIntersects(coordinates)) {
      throw new BadRequestException({
        code: 'ERR_302',
        message:
          'SELF_INTERSECT: Đường biên tự cắt (hình số 8, đi lại ô cũ) hoặc các ô không theo thứ tự đường chạy.',
      });
    }

    // 4. Lấy tất cả các ô H3 Res 10 có tâm nằm bên trong đa giác
    const enclosed = h3.polygonToCells(coordinates, H3_RESOLUTION, false);
    const combined = Array.from(new Set([...ring, ...enclosed]));

    if (combined.length > this.MAX_HEX_PER_LOOP) {
      throw new BadRequestException({
        code: 'ERR_301',
        message: `LOOP_TOO_LARGE: Tổng diện tích khép vòng (${combined.length} ô) vượt quá giới hạn tối đa 150 ô H3.`,
      });
    }

    return combined;
  }

  /** Có hai cạnh không kề nhau của đa giác khép kín nào chạm/cắt nhau không. O(n²), n ≤ 150. */
  private selfIntersects(points: Point[]): boolean {
    const n = points.length;
    const edge = (i: number): [Point, Point] => [points[i], points[(i + 1) % n]];
    for (let i = 0; i < n; i++) {
      for (let j = i + 2; j < n; j++) {
        if (i === 0 && j === n - 1) continue; // cạnh đầu và cạnh cuối chung đỉnh đầu
        if (segmentsTouch(...edge(i), ...edge(j))) return true;
      }
    }
    return false;
  }
}

function orientation(a: Point, b: Point, c: Point): number {
  const v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
  return Math.abs(v) < 1e-18 ? 0 : Math.sign(v);
}

function onSegment(a: Point, b: Point, p: Point): boolean {
  return (
    Math.min(a[0], b[0]) <= p[0] && p[0] <= Math.max(a[0], b[0]) &&
    Math.min(a[1], b[1]) <= p[1] && p[1] <= Math.max(a[1], b[1])
  );
}

function segmentsTouch(p1: Point, p2: Point, q1: Point, q2: Point): boolean {
  const o1 = orientation(p1, p2, q1);
  const o2 = orientation(p1, p2, q2);
  const o3 = orientation(q1, q2, p1);
  const o4 = orientation(q1, q2, p2);
  if (o1 !== o2 && o3 !== o4) return true;
  return (
    (o1 === 0 && onSegment(p1, p2, q1)) ||
    (o2 === 0 && onSegment(p1, p2, q2)) ||
    (o3 === 0 && onSegment(q1, q2, p1)) ||
    (o4 === 0 && onSegment(q1, q2, p2))
  );
}
