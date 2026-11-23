import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, ManyToOne, JoinColumn, OneToMany } from 'typeorm';
import { University } from './university.entity';
import { RunningSession } from './running-session.entity';

@Entity('users')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true, length: 255 })
  email: string;

  @Column({ length: 50, nullable: true })
  display_name: string;

  @Column({ type: 'float', default: 0.0 })
  personal_km: number;

  @ManyToOne(() => University, (uni) => uni.users, { nullable: true })
  @JoinColumn({ name: 'university_id' })
  university: University;

  @Column({ nullable: true })
  university_id: string;

  @Column({ length: 10, default: 'user' })
  role: UserRole;

  /** Hết hạn cấm chơi; null = không bị cấm. Cấm vĩnh viễn = năm 9999. */
  @Column({ type: 'timestamptz', nullable: true })
  banned_until: Date | null;

  @CreateDateColumn()
  created_at: Date;

  @OneToMany(() => RunningSession, (session) => session.user)
  sessions: RunningSession[];
}

export type UserRole = 'user' | 'admin';
