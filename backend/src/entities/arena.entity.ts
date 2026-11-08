import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, OneToMany } from 'typeorm';
import { H3Hexagon } from './h3-hexagon.entity';

@Entity('arenas')
export class Arena {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ length: 100 })
  name: string;

  @Column({ type: 'text', nullable: true })
  description: string;

  /** Ranh giới gốc (PostGIS). TypeORM tự đọc/ghi dưới dạng GeoJSON. */
  @Column({ type: 'geometry', spatialFeatureType: 'Polygon', srid: 4326, nullable: true })
  boundary_polygon: { type: 'Polygon'; coordinates: number[][][] } | null;

  /** Số bịa trong seed; dùng số ô đếm thật thay thế (ticket wayfinder #5). */
  @Column({ type: 'int', default: 0 })
  total_hexes: number;

  @Column({ default: true })
  is_active: boolean;

  @CreateDateColumn()
  created_at: Date;

  @OneToMany(() => H3Hexagon, (hex) => hex.arena)
  hexagons: H3Hexagon[];
}
