import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { User } from './user.entity';
import { RunningSession } from './running-session.entity';

@Entity('gigo_audit_logs')
export class GigoAuditLog {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid', nullable: true })
  user_id: string;

  @ManyToOne(() => User, { nullable: true, onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ type: 'uuid', nullable: true })
  session_id: string;

  @ManyToOne(() => RunningSession, { nullable: true, onDelete: 'SET NULL' })
  @JoinColumn({ name: 'session_id' })
  session: RunningSession;

  @Column({ length: 50 })
  rejection_type: string;

  @Column({ type: 'float' })
  raw_gps_speed_mps: number;

  @Column({ type: 'int' })
  imu_cadence_spm: number;

  @Column({ type: 'float', nullable: true })
  vertical_energy_g: number;

  @Column({ type: 'float', nullable: true })
  gps_accuracy_m: number;

  @Column({ length: 15, nullable: true })
  detected_at_h3: string;

  @CreateDateColumn({ type: 'timestamptz' })
  created_at: Date;
}
