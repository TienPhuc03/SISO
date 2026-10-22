import { Entity, PrimaryColumn, Column, UpdateDateColumn, ManyToOne, JoinColumn } from 'typeorm';
import { University } from './university.entity';
import { Arena } from './arena.entity';

@Entity('h3_hexagons')
export class H3Hexagon {
  @PrimaryColumn({ length: 15 })
  h3_index: string;

  @ManyToOne(() => Arena, { nullable: true })
  @JoinColumn({ name: 'arena_id' })
  arena: Arena;

  @Column({ nullable: true })
  arena_id: string;

  @ManyToOne(() => University, (uni) => uni.hexagons, { nullable: true })
  @JoinColumn({ name: 'owner_university_id' })
  ownerUniversity: University;

  @Column({ nullable: true })
  owner_university_id: string;

  @Column({ type: 'int', default: 100 })
  shield_hp: number;

  @Column({ type: 'timestamptz', default: () => 'CURRENT_TIMESTAMP' })
  last_patrolled_at: Date;

  @UpdateDateColumn()
  updated_at: Date;
}
