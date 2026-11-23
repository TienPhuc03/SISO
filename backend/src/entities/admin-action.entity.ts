import { Entity, PrimaryGeneratedColumn, Column, CreateDateColumn } from 'typeorm';

/** Nhật ký thao tác của admin (ai làm gì, lên đối tượng nào). */
@Entity('admin_actions')
export class AdminAction {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'uuid', nullable: true })
  admin_id: string | null;

  @Column({ length: 50 })
  action: string;

  @Column({ length: 30 })
  target_type: string;

  @Column({ length: 64, nullable: true })
  target_id: string | null;

  @Column({ type: 'jsonb', default: () => "'{}'::jsonb" })
  payload: Record<string, unknown>;

  @CreateDateColumn({ type: 'timestamptz' })
  created_at: Date;
}
