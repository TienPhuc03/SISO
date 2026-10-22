import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
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

  @CreateDateColumn()
  created_at: Date;
}
