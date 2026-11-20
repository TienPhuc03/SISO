import { Entity, PrimaryColumn, Column, ManyToOne, JoinColumn } from 'typeorm';
import { RunningSession } from './running-session.entity';

/** Một điểm GPS client ghi trong cửa sổ (timestamp: epoch mili giây, accuracy: mét). */
export interface GpsPoint {
  lat: number;
  lng: number;
  timestamp: number;
  accuracy: number;
}

/** Một cửa sổ 5,12 s đã qua Cổng Động học của Phiên chạy: vệt GPS + tốc độ/nhịp bước. */
@Entity('session_windows')
export class SessionWindow {
  @PrimaryColumn({ type: 'uuid' })
  session_id: string;

  @ManyToOne(() => RunningSession, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'session_id' })
  session: RunningSession;

  /** Cửa sổ đầu = 0, các cửa sổ sau = seq client đã ký. */
  @PrimaryColumn({ type: 'int' })
  seq: number;

  @Column({ type: 'float' })
  speed_mps: number;

  @Column({ type: 'int', default: 0 })
  cadence_spm: number;

  /** false = cửa sổ chỉ bị cảnh báo ở Cổng Sinh trắc. */
  @Column()
  passed: boolean;

  @Column({ type: 'jsonb', default: () => "'[]'::jsonb" })
  gps_points: GpsPoint[];

  @Column({ type: 'timestamptz' })
  recorded_at: Date;
}
