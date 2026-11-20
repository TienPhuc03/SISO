import { Entity, PrimaryColumn, Column, OneToOne, JoinColumn } from 'typeorm';
import { User } from './user.entity';

/**
 * Ảnh đại diện của Sinh viên (đã thu nhỏ trên máy). Tách khỏi `users` vì bảng đó cho đọc công khai,
 * còn bảng này bật RLS không policy: chỉ backend đọc được.
 */
@Entity('user_avatars')
export class UserAvatar {
  @PrimaryColumn({ type: 'uuid' })
  user_id: string;

  @OneToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ type: 'bytea' })
  image: Buffer;

  /** image/jpeg | image/png | image/webp, xác định theo byte đầu file chứ không theo client báo. */
  @Column({ length: 20 })
  mime_type: string;

  @Column({ type: 'timestamptz' })
  updated_at: Date;
}
