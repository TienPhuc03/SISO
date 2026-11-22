import { DataSource } from 'typeorm';
import { PatrolReminderService } from './patrol-reminder.service';
import { PushService } from './push.service';

describe('PatrolReminderService', () => {
  const now = new Date('2026-11-22T12:00:00.000Z');
  let query: jest.Mock;
  let sendToTopic: jest.Mock;
  let service: PatrolReminderService;

  beforeEach(() => {
    query = jest.fn();
    sendToTopic = jest.fn().mockResolvedValue(undefined);
    service = new PatrolReminderService(
      { query } as unknown as DataSource,
      { enabled: true, sendToTopic } as unknown as PushService,
    );
  });

  it('chỉ xét Ô Tuần tra lần cuối trong khung (43h, 42h] trước đây, tức còn ~6h là về Trung lập', async () => {
    query.mockResolvedValue([]);
    await service.remind(now);

    const [, [from, to]] = query.mock.calls[0];
    expect(from).toEqual(new Date('2026-11-20T17:00:00.000Z'));
    expect(to).toEqual(new Date('2026-11-20T18:00:00.000Z'));
    expect(sendToTopic).not.toHaveBeenCalled();
  });

  it('gửi một thông báo vào topic của mỗi trường; trường lỗi không chặn trường khác', async () => {
    query.mockResolvedValue([
      { university_id: 'uni-a', count: 3 },
      { university_id: 'uni-b', count: 1 },
    ]);
    sendToTopic.mockRejectedValueOnce(new Error('fcm down'));

    expect(await service.remind(now)).toBe(1);
    expect(sendToTopic).toHaveBeenCalledTimes(2);
    expect(sendToTopic).toHaveBeenLastCalledWith(
      'university_uni-b',
      'Ô đất sắp về Trung lập',
      expect.stringContaining('1 Ô đất'),
      { type: 'patrol_reminder', count: '1' },
    );
  });
});
