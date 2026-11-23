import { Injectable } from '@nestjs/common';
import { DataSource, EntityManager } from 'typeorm';
import { AdminAction } from '../../entities/admin-action.entity';

export type AdminTargetType = 'user' | 'gigo_log' | 'season' | 'university' | 'arena';

/** Ghi và đọc nhật ký thao tác admin. Ghi bằng `manager` của transaction đang chạy để cùng commit/rollback. */
@Injectable()
export class AdminAuditService {
  constructor(private readonly dataSource: DataSource) {}

  log(
    manager: EntityManager,
    adminId: string,
    action: string,
    targetType: AdminTargetType,
    targetId: string | null,
    payload: Record<string, unknown> = {},
  ) {
    return manager.insert(AdminAction, { admin_id: adminId, action, target_type: targetType, target_id: targetId, payload });
  }

  async list(page: number, limit: number, targetType?: string, targetId?: string) {
    const params: unknown[] = [];
    const where: string[] = [];
    if (targetType) where.push(`a.target_type = $${params.push(targetType)}`);
    if (targetId) where.push(`a.target_id = $${params.push(targetId)}`);
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const [items, [{ total }]] = await Promise.all([
      this.dataSource.query(
        `SELECT a.id, a.action, a.target_type AS "targetType", a.target_id AS "targetId", a.payload,
                a.created_at AS "createdAt", u.email AS "adminEmail"
         FROM public.admin_actions a LEFT JOIN public.users u ON u.id = a.admin_id
         ${whereSql} ORDER BY a.created_at DESC
         LIMIT $${params.length + 1} OFFSET $${params.length + 2}`,
        [...params, limit, (page - 1) * limit],
      ),
      this.dataSource.query(`SELECT COUNT(*)::int AS total FROM public.admin_actions a ${whereSql}`, params),
    ]);
    return { items, total, page, limit };
  }
}
