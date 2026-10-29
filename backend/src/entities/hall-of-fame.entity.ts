import {
  Entity,
  PrimaryGeneratedColumn,
  Column,
  CreateDateColumn,
  ManyToOne,
  JoinColumn,
} from 'typeorm';
import { Season } from './season.entity';
import { University } from './university.entity';

@Entity('hall_of_fame')
export class HallOfFame {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'int' })
  season_number: number;

  @ManyToOne(() => Season, (season) => season.hall_of_fame_records, {
    onDelete: 'CASCADE',
  })
  @JoinColumn({ name: 'season_number' })
  season: Season;

  @Column({ type: 'uuid' })
  champion_university_id: string;

  @ManyToOne(() => University, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'champion_university_id' })
  championUniversity: University;

  @Column({ type: 'float', default: 0.0 })
  territory_pct: number;

  @Column({ type: 'float', default: 0.0 })
  mileage_pct: number;

  @Column({ type: 'float', default: 0.0 })
  composite_power_pct: number;

  @CreateDateColumn({ type: 'timestamptz' })
  recorded_at: Date;
}
