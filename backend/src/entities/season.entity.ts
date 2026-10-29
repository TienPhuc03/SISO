import { Entity, PrimaryColumn, Column, CreateDateColumn, OneToMany } from 'typeorm';
import { HallOfFame } from './hall-of-fame.entity';

@Entity('seasons')
export class Season {
  @PrimaryColumn({ type: 'int' })
  season_number: number;

  @Column({ type: 'date' })
  start_date: string;

  @Column({ type: 'date' })
  end_date: string;

  @Column({ default: true })
  is_active: boolean;

  @CreateDateColumn({ type: 'timestamptz' })
  created_at: Date;

  @OneToMany(() => HallOfFame, (hof) => hof.season)
  hall_of_fame_records: HallOfFame[];
}
