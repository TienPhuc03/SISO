import { Injectable, BadRequestException } from '@nestjs/common';
import * as h3 from 'h3-js';

@Injectable()
export class H3Service {
  private readonly MAX_HEX_PER_LOOP = 150; // Giới hạn an toàn chống lạm dụng (ERR_301)

  /**
   * Tính toán tập hợp các ô lục giác nằm trong chu trình khép kín (Flood Fill / Polygon to Cells)
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

    try {
      // 2. Chuyển đổi các chỉ số H3 đường biên thành tọa độ Geo Polygon
      const coordinates: [number, number][] = boundaryIndexes.map((hex) => {
        const [lat, lng] = h3.cellToLatLng(hex);
        return [lat, lng];
      });

      // Đảm bảo đa giác khép kín điểm đầu và điểm cuối
      if (coordinates.length >= 3) {
        const first = coordinates[0];
        const last = coordinates[coordinates.length - 1];
        if (first[0] !== last[0] || first[1] !== last[1]) {
          coordinates.push([first[0], first[1]]);
        }

        // Lấy tất cả các ô H3 Res 10 nằm trọn bên trong đa giác
        const enclosed = h3.polygonToCells(coordinates, 10, true);
        const combined = Array.from(new Set([...boundaryIndexes, ...enclosed]));

        if (combined.length > this.MAX_HEX_PER_LOOP) {
          throw new BadRequestException({
            code: 'ERR_301',
            message: `LOOP_TOO_LARGE: Tổng diện tích khép vòng (${combined.length} ô) vượt quá giới hạn tối đa 150 ô H3.`,
          });
        }

        return combined;
      }

      return Array.from(new Set(boundaryIndexes));
    } catch (err) {
      if (err instanceof BadRequestException) throw err;
      // Fallback trả về danh sách các ô trên đường biên nếu lỗi hình học
      return Array.from(new Set(boundaryIndexes));
    }
  }
}
