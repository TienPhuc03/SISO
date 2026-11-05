import { ApiProperty } from '@nestjs/swagger';

export class HexagonResponseDto {
  @ApiProperty({ example: '8a65b56718b7fff', description: 'Mã ô H3 res 10' })
  h3Index: string;

  @ApiProperty({ example: 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a', nullable: true })
  arenaId: string | null;

  @ApiProperty({ example: 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a', nullable: true, description: 'null = ô trung lập' })
  ownerUniversityId: string | null;

  @ApiProperty({ example: 'HUTECH', nullable: true })
  universityCode: string | null;

  @ApiProperty({ example: '#FFCC00', description: '#RRGGBB của trường, hoặc #44FFFFFF cho ô trung lập' })
  hexColor: string;

  @ApiProperty({ example: 100 })
  shieldHp: number;

  @ApiProperty({ example: '2026-11-04T10:00:00.000Z' })
  lastPatrolledAt: Date;
}

export class GeoJsonPolygonDto {
  @ApiProperty({ example: 'Polygon' })
  type: 'Polygon';

  @ApiProperty({
    example: [[[106.7185, 10.791], [106.7255, 10.791], [106.7255, 10.7985], [106.7185, 10.791]]],
    description: 'Mảng vòng [lng, lat] theo chuẩn GeoJSON',
  })
  coordinates: number[][][];
}

export class ArenaResponseDto {
  @ApiProperty({ example: 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a' })
  id: string;

  @ApiProperty({ example: 'Công Viên Landmark 81' })
  name: string;

  @ApiProperty({ example: 'Quần thể công viên ven sông Central Park', nullable: true })
  description: string | null;

  @ApiProperty({ example: 25, description: 'Số ô đếm thật trong h3_hexagons' })
  hexCount: number;

  @ApiProperty({ type: GeoJsonPolygonDto, nullable: true })
  boundary: GeoJsonPolygonDto | null;
}

class BaseListResponseDto {
  @ApiProperty({ example: true })
  success: boolean;

  @ApiProperty({ example: 'Thao tác thành công.' })
  message: string;

  @ApiProperty({ example: '2026-11-04T10:00:00.000Z' })
  timestamp: string;
}

/** Chỉ dùng cho Swagger: hình dạng BaseResponseDto với data là mảng ô. */
export class HexagonListResponseDto extends BaseListResponseDto {
  @ApiProperty({ type: [HexagonResponseDto] })
  data: HexagonResponseDto[];
}

/** Chỉ dùng cho Swagger: hình dạng BaseResponseDto với data là mảng Đấu trường. */
export class ArenaListResponseDto extends BaseListResponseDto {
  @ApiProperty({ type: [ArenaResponseDto] })
  data: ArenaResponseDto[];
}
