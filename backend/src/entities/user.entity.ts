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

  @CreateDateColumn()
  created_at: Date;

  @OneToMany(() => RunningSession, (session) => session.user)
  sessions: RunningSession[];
}
