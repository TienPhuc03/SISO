import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  UpdateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { User } from './user.entity';

@Entity('running_sessions')
export class RunningSession {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @ManyToOne(() => User, (user) => user.sessions, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column()
  user_id: string;

  @Column({ default: 'ARENA_LOOP' })
  session_type: string;

  @Column({ type: 'float' })
  distance_meters: number;

  @Column({ type: 'int' })
  duration_seconds: number;

  @Column({ type: 'int', default: 0 })
  hex_count: number;

  @Column({ default: true })
  is_valid: boolean;

  @Column({ nullable: true, length: 50 })
  rejection_reason: string;

  /** ACTIVE (đang chạy) → REJECTED (Phiên bị loại) | COMPLETED (đã kết thúc). */
  @Column({ length: 20, default: 'COMPLETED' })
  status: RunStatus;

  /** Số cửa sổ liên tiếp không qua Cổng Sinh trắc; đạt 2 thì Phiên chạy bị loại. */
  @Column({ type: 'int', default: 0 })
  consecutive_biometric_failures: number;

  /** Số thứ tự lớn nhất đã nhận; cửa sổ có seq không lớn hơn là gửi lại (ERR_205). */
  @Column({ type: 'int', default: 0 })
  last_window_seq: number;

  @CreateDateColumn()
  created_at: Date;

  @UpdateDateColumn()
  updated_at: Date;
}

export type RunStatus = 'ACTIVE' | 'REJECTED' | 'COMPLETED';
