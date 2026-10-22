import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn, OneToMany } from 'typeorm';
import { User } from './user.entity';
import { H3Hexagon } from './h3-hexagon.entity';

@Entity('universities')
export class University {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ unique: true, length: 20 })
  short_code: string;

  @Column({ length: 100 })
  name: string;

  @Column({ unique: true, length: 50 })
  email_domain: string;

  @Column({ length: 7 })
  hex_color: string;

  @Column({ length: 7, nullable: true })
  secondary_color: string;

  @Column({ type: 'float', default: 0.0 })
  total_season_km: number;

  @Column({ type: 'text', nullable: true })
  logo_url: string;

  @CreateDateColumn()
  created_at: Date;

  @OneToMany(() => User, (user) => user.university)
  users: User[];

  @OneToMany(() => H3Hexagon, (hex) => hex.ownerUniversity)
  hexagons: H3Hexagon[];
}
