/** LINE Messaging API: ส่งข้อความหาผู้ใช้/กลุ่มที่เป็นเพื่อนกับ Official Account */
export const LINE_PUSH_URL = 'https://api.line.me/v2/bot/message/push';

export type FetchLike = (
  url: string,
  init: { method: string; headers: Record<string, string>; body: string },
) => Promise<{ ok: boolean; status: number }>;

export type LineMessage = Record<string, unknown>;

/** ส่ง push 1 ครั้ง คืน HTTP status (throw เฉพาะเมื่อเครือข่ายล่ม) */
export async function linePush(
  fetchImpl: FetchLike,
  token: string,
  to: string,
  messages: LineMessage[],
): Promise<{ ok: boolean; status: number }> {
  return fetchImpl(LINE_PUSH_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ to, messages }),
  });
}
