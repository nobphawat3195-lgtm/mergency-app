// Run the built API against an explicitly selected, disposable local database.
// Never use credentials or notification/payment providers from the caller's environment.
const assert = require('node:assert/strict');
const { spawn } = require('node:child_process');
const { createHmac, randomBytes, scryptSync } = require('node:crypto');
const { mkdtemp, rm } = require('node:fs/promises');
const net = require('node:net');
const { tmpdir } = require('node:os');
const path = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');
const { PrismaClient } = require('@prisma/client');

const databaseUrl = process.env.FIXGO_TEST_DATABASE_URL;
if (!databaseUrl) throw new Error('Set FIXGO_TEST_DATABASE_URL');
const database = new URL(databaseUrl);
if (!['localhost', '127.0.0.1'].includes(database.hostname) || database.pathname !== '/fixgo_audit_test') {
  throw new Error('HTTP tests only accept local fixgo_audit_test');
}
const prisma = new PrismaClient({ datasources: { db: { url: databaseUrl } } });
let api;
let uploads;
let baseUrl;
let passed = 0;
let startupLogs = '';
const jwtSecret = randomBytes(32).toString('hex');

/** โทเคนช่างที่เข้าด้วย LINE แต่ยังไม่สมัคร (เหมือนที่ /auth/line/exchange ออกให้) */
function pendingLineToken(lineUserId) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const body = `${encode({ alg: 'HS256', typ: 'JWT' })}.${encode({
    sub: `pending:line:${lineUserId}`,
    role: 'PROVIDER',
    phone: '',
    lineUserId,
    iat: now,
    exp: now + 3600,
  })}`;
  return `${body}.${createHmac('sha256', jwtSecret).update(body).digest('base64url')}`;
}

async function request(method, route, token, body, expected) {
  const response = await fetch(`${baseUrl}/api${route}`, {
    method,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(10000),
  });
  const text = await response.text();
  let result;
  try {
    result = JSON.parse(text);
  } catch {
    result = text;
  }
  if (expected !== undefined) assert.equal(response.status, expected, `${method} ${route}: ${text}`);
  return { status: response.status, body: result, headers: response.headers };
}
/** ปิดงาน: แนบรูปรถหลังซ่อมที่ช่างอัปโหลดเอง 1 รูป */
async function closeJob(token, orderId, expected) {
  const carPhotoUrls = [await uploadImage(token, 'ORDER')];
  return request('POST', `/orders/${orderId}/complete`, token, { carPhotoUrls }, expected);
}
/** บันทึก audit ของแอดมินเขียนหลังส่ง response แล้ว (ไม่ให้งานหลักช้า) ต้องรอให้แถวมาถึงก่อนนับ */
async function auditCount(where, atLeast) {
  let count = 0;
  for (let i = 0; i < 30; i++) {
    count = await prisma.adminAuditLog.count({ where });
    if (count >= atLeast) break;
    await delay(100);
  }
  return count;
}
async function check(name, run) {
  await run();
  passed += 1;
  console.log(`PASS ${name}`);
}
async function login(phone, role) {
  const otp = (await request('POST', '/auth/otp/request', undefined, { phone, role }, 201)).body;
  assert.match(otp.devCode, /^\d{6}$/);
  const session = (await request('POST', '/auth/otp/verify', undefined, { phone, role, code: otp.devCode }, 201)).body;
  assert.ok(session.accessToken);
  await request('POST', '/auth/otp/verify', undefined, { phone, role, code: otp.devCode }, 401);
  return session.accessToken;
}
async function uploadImage(token, scope) {
  const bytes = Buffer.from(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1cAAAAASUVORK5CYII=',
    'base64',
  );
  const signed = (
    await request(
      'POST',
      '/uploads/presign',
      token,
      {
        fileName: 'test.png',
        contentType: 'image/png',
        byteLength: bytes.length,
        scope,
      },
      201,
    )
  ).body;
  const put = await fetch(signed.uploadUrl, {
    method: 'PUT',
    headers: signed.headers,
    body: bytes,
    signal: AbortSignal.timeout(10000),
  });
  assert.equal(put.status, 200);
  const replay = await fetch(signed.uploadUrl, {
    method: 'PUT',
    headers: signed.headers,
    body: bytes,
    signal: AbortSignal.timeout(10000),
  });
  assert.equal(replay.status, 409);
  const image = await fetch(signed.publicUrl, {
    signal: AbortSignal.timeout(10000),
  });
  assert.equal(image.status, 200);
  assert.equal(image.headers.get('x-content-type-options'), 'nosniff');
  assert.deepEqual(Buffer.from(await image.arrayBuffer()), bytes);
  return signed.publicUrl;
}

async function main() {
  await prisma.$connect();
  await prisma.$executeRawUnsafe(
    'TRUNCATE "Customer", "Provider", "ServiceCategory", "VehicleType", "OtpCode", "AdminUser" CASCADE',
  );
  const category = await prisma.serviceCategory.create({
    data: { slug: 'repair', name: 'Test repair', iconKey: 'repair' },
  });
  const service = await prisma.subService.create({
    data: {
      categoryId: category.id,
      name: 'Test service',
      basePrice: 10000,
      priceType: 'FULL_SERVICE',
    },
  });
  const vehicle = await prisma.vehicleType.create({
    data: { slug: 'car', name: 'Car' },
  });
  const inspectionCategory = await prisma.serviceCategory.create({
    data: {
      slug: 'used-car-inspection',
      name: 'Inspection',
      iconKey: 'inspection',
    },
  });
  const inspectionService = await prisma.subService.create({
    data: {
      categoryId: inspectionCategory.id,
      name: 'Inspection',
      basePrice: 199000,
      priceType: 'FULL_SERVICE',
      fixedPrice: true,
    },
  });
  const provider = await prisma.provider.create({
    data: {
      phone: '0800000002',
      realName: 'HTTP test',
      nickname: 'Test',
      experienceYears: 5,
      baseLat: 13.7,
      baseLng: 100.5,
      openMinute: 0,
      closeMinute: 1439,
      bankName: 'Test bank',
      bankAccountName: 'HTTP test',
      bankAccountNumber: '1234567890',
      serviceCategories: {
        create: [{ categoryId: category.id }, { categoryId: inspectionCategory.id }],
      },
      vehicleTypes: { create: { vehicleTypeId: vehicle.id } },
    },
  });
  const password = randomBytes(24).toString('hex');
  const salt = randomBytes(16).toString('hex');
  const passwordHash = `${salt}:${scryptSync(password, salt, 64).toString('hex')}`;
  await prisma.adminUser.createMany({
    data: [
      { phone: '0800000004', name: 'Owner test', role: 'OWNER', passwordHash },
      { phone: '0800000005', name: 'Staff test', role: 'STAFF', passwordHash },
    ],
  });
  const portServer = net.createServer();
  await new Promise((resolve) => portServer.listen(0, '127.0.0.1', resolve));
  const port = portServer.address().port;
  await new Promise((resolve) => portServer.close(resolve));
  baseUrl = `http://127.0.0.1:${port}`;
  uploads = await mkdtemp(path.join(tmpdir(), 'fixgo-http-'));
  api = spawn(process.execPath, ['dist/main.js'], {
    cwd: path.resolve(__dirname, '..'),
    env: {
      PATH: process.env.PATH,
      NODE_ENV: 'development',
      PORT: String(port),
      DATABASE_URL: databaseUrl,
      JWT_SECRET: jwtSecret,
      OTP_SECRET: randomBytes(32).toString('hex'),
      PAYMENT_WEBHOOK_SECRET: randomBytes(32).toString('hex'),
      STORAGE_PROVIDER: 'local',
      UPLOAD_DIR: uploads,
      PUBLIC_API_URL: baseUrl,
      PUBLIC_WEB_URL: 'http://localhost:8080',
      CORS_ORIGIN: 'http://localhost:8080',
      SMS_PROVIDER: 'console',
      PUSH_PROVIDER: 'console',
      ADMIN_ALERT_CHANNEL: 'none',
      PAYMENT_PROVIDER: 'promptpay_manual',
      PROMPTPAY_ID: '0800000099',
      PROMPTPAY_NAME: 'Test only',
      COMMISSION_RATE: '0.35',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  api.stdout.on('data', (chunk) => {
    startupLogs = (startupLogs + chunk).slice(-6000);
  });
  api.stderr.on('data', (chunk) => {
    startupLogs = (startupLogs + chunk).slice(-6000);
  });
  let ready = false;
  for (let i = 0; i < 100; i++) {
    if (api.exitCode !== null) throw new Error(`API exited before startup: ${startupLogs}`);
    try {
      ready = (await request('GET', '/health')).status === 200;
    } catch {}
    if (ready) break;
    await delay(100);
  }
  assert.ok(ready, 'API did not become healthy');
  let customer, stranger, mechanic, owner, staff, order, secondOrder, slip;
  const booking = {
    categoryId: category.id,
    subServiceId: service.id,
    vehicleTypeId: vehicle.id,
    pickupLat: 13.7,
    pickupLng: 100.5,
  };
  await check('API health connects to PostgreSQL', async () => {
    assert.equal((await request('GET', '/health', undefined, undefined, 200)).body.database, 'up');
  });
  await check('DTO validation and unauthenticated access', async () => {
    await request('POST', '/auth/otp/request', undefined, { phone: 'bad', role: 'CUSTOMER' }, 400);
    await request('GET', '/orders/mine', undefined, undefined, 401);
  });
  await check('Customer/provider OTP and owner/staff logins', async () => {
    customer = await login('0800000001', 'CUSTOMER');
    stranger = await login('0800000003', 'CUSTOMER');
    mechanic = await login(provider.phone, 'PROVIDER');
    owner = (await request('POST', '/admin/login', undefined, { phone: '0800000004', password }, 201)).body.accessToken;
    staff = (await request('POST', '/admin/login', undefined, { phone: '0800000005', password }, 201)).body.accessToken;
  });
  await check('Customer reads own account; other roles cannot', async () => {
    const me = (await request('GET', '/account', customer, undefined, 200)).body;
    assert.equal(me.phone, '0800000001');
    assert.equal(me.viaLine, false);
    await request('GET', '/account', mechanic, undefined, 403);
    await request('GET', '/account', undefined, undefined, 401);
  });
  await check('Concurrent reuse of one OTP permits only one login', async () => {
    const phone = '0800000006';
    const otp = (await request('POST', '/auth/otp/request', undefined, { phone, role: 'CUSTOMER' }, 201)).body;
    const results = await Promise.all(
      Array.from({ length: 5 }, () =>
        request('POST', '/auth/otp/verify', undefined, {
          phone,
          role: 'CUSTOMER',
          code: otp.devCode,
        }),
      ),
    );
    assert.equal(results.filter((result) => result.status === 201).length, 1);
    assert.equal(results.filter((result) => result.status === 401).length, 4);
  });
  await check('Concurrent OTP requests send one code and enforce cooldown', async () => {
    const phone = '0800000007';
    const results = await Promise.all(
      Array.from({ length: 5 }, () =>
        request('POST', '/auth/otp/request', undefined, {
          phone,
          role: 'CUSTOMER',
        }),
      ),
    );
    assert.equal(results.filter((result) => result.status === 201).length, 1);
    assert.equal(results.filter((result) => result.status === 429).length, 4);
    assert.equal(await prisma.otpCode.count({ where: { phone, consumed: false } }), 1);
    const issued = results.find((result) => result.status === 201).body;
    const wrong = issued.devCode === '000000' ? '111111' : '000000';
    await Promise.all(
      Array.from({ length: 6 }, () =>
        request('POST', '/auth/otp/verify', undefined, { phone, role: 'CUSTOMER', code: wrong }, 401),
      ),
    );
    await request('POST', '/auth/otp/verify', undefined, { phone, role: 'CUSTOMER', code: issued.devCode }, 401);
  });
  await check('Role separation and mechanic approval', async () => {
    await request('GET', '/admin/finance', staff, undefined, 403);
    await request('GET', '/admin/finance', customer, undefined, 403);
    await request('PATCH', '/providers/me/online', mechanic, { isOnline: true }, 403);
    await request('PATCH', `/admin/providers/${provider.id}/status`, owner, { status: 'VERIFIED' }, 200);
    await request('PATCH', '/providers/me/online', mechanic, { isOnline: true }, 200);
    await request('POST', '/providers/me/heartbeat', mechanic, undefined, 201);
  });
  await check('Booking creates a real dispatch offer', async () => {
    order = (await request('POST', '/orders', customer, booking, 201)).body;
    assert.equal(order.status, 'SEARCHING');
    assert.ok(
      (await request('GET', '/dispatch/offers', mechanic, undefined, 200)).body.some(
        (offer) => offer.orderId === order.id,
      ),
    );
    await request('GET', `/orders/${order.id}`, stranger, undefined, 404);
  });
  await check('Accept, journey and stale price approval', async () => {
    await request('POST', `/dispatch/offers/${order.id}/accept`, mechanic, undefined, 201);
    await request('PATCH', `/orders/${order.id}/en-route`, mechanic, undefined, 200);
    await request('PATCH', `/orders/${order.id}/start`, mechanic, undefined, 400);
    await request('POST', `/orders/${order.id}/quote`, mechanic, { priceProposed: 10000 }, 201);
    const quote = (await request('GET', `/orders/${order.id}`, customer, undefined, 200)).body;
    await request('POST', `/orders/${order.id}/quote/approve`, customer, {}, 400);
    await request(
      'POST',
      `/orders/${order.id}/quote/approve`,
      customer,
      { quoteVersion: quote.quoteVersion - 1, priceProposed: 10000 },
      409,
    );
    await request(
      'POST',
      `/orders/${order.id}/quote/approve`,
      customer,
      { quoteVersion: quote.quoteVersion, priceProposed: 10000 },
      201,
    );
    await request('POST', `/orders/${order.id}/quote`, mechanic, { priceProposed: 12000 }, 409);
  });
  await check('Public tracking exposes no price or phone and can be revoked', async () => {
    const shared = (await request('POST', `/orders/${order.id}/share`, customer, undefined, 201)).body;
    const view = await request('GET', `/public/track/${shared.token}`, undefined, undefined, 200);
    assert.equal(view.headers.get('cache-control'), 'no-store');
    assert.equal(view.body.priceFinal, undefined);
    assert.equal(view.body.provider.phone, undefined);
    await request('DELETE', `/orders/${order.id}/share`, customer, undefined, 200);
    await request('GET', `/public/track/${shared.token}`, undefined, undefined, 404);
  });
  await check('Order chat: only the customer and assigned mechanic can read or send', async () => {
    const path = `/orders/${order.id}/messages`;
    const sent = (await request('POST', path, customer, { text: '  ถึงประมาณกี่โมงครับ  ' }, 201)).body;
    assert.equal(sent.text, 'ถึงประมาณกี่โมงครับ');
    assert.equal(sent.sender, 'CUSTOMER');
    const photo = await uploadImage(mechanic, 'ORDER');
    await request('POST', path, mechanic, { text: 'อีก 10 นาทีครับ', imageUrl: photo }, 201);
    // รูปของคนอื่น/ลิงก์ภายนอกส่งไม่ได้
    await request('POST', path, customer, { imageUrl: photo }, 400);
    await request('POST', path, customer, { imageUrl: 'https://evil.example/x.png' }, 400);
    await request('POST', path, customer, { text: '   ' }, 400);
    await request('POST', path, customer, { text: 'x'.repeat(1001) }, 400);

    // คนนอกงานอ่าน/ส่งไม่ได้ และไม่รู้ว่างานมีอยู่จริง
    await request('GET', path, stranger, undefined, 404);
    await request('POST', path, stranger, { text: 'hi' }, 404);
    await request('GET', path, owner, undefined, 403);
    await request('GET', path, undefined, undefined, 401);

    // badge: ลูกค้ามีข้อความใหม่จากช่าง 1 ข้อความ เปิดอ่านแล้วเป็น 0
    assert.equal((await request('GET', `/orders/${order.id}`, customer, undefined, 200)).body.chatUnread, 1);
    const opened = (await request('GET', path, customer, undefined, 200)).body;
    assert.equal(opened.canSend, true);
    assert.deepEqual(opened.messages.map((m) => m.sender), ['CUSTOMER', 'PROVIDER']);
    assert.equal(opened.messages[1].imageUrl, photo);
    const detail = (await request('GET', `/orders/${order.id}`, customer, undefined, 200)).body;
    assert.equal(detail.chatUnread, 0);
    assert.equal(detail.chatOpen, true);
    // ช่างตอบแล้วถือว่าอ่านข้อความก่อนหน้า ข้อความใหม่หลังจากนั้นนับเป็น badge
    await request('POST', path, customer, { text: 'โอเคครับ' }, 201);
    const assigned = (await request('GET', '/orders/assigned', mechanic, undefined, 200)).body;
    assert.equal(assigned.find((o) => o.id === order.id).chatUnread, 1);

    // แอดมินเปิดอ่านได้และมีบันทึก
    const forAdmin = (await request('GET', `/admin/orders/${order.id}/messages`, staff, undefined, 200)).body;
    assert.equal(forAdmin.messages.length, 3);
    assert.equal(await auditCount({ action: 'ORDER_CHAT_READ', targetId: order.id }, 1), 1);
    await request('GET', `/admin/orders/${order.id}/messages`, customer, undefined, 403);
  });
  await check('Complete and confirm cash twice without duplicate commission', async () => {
    await request('PATCH', `/orders/${order.id}/start`, mechanic, undefined, 200);
    // ต้องมีรูปรถหลังซ่อมอย่างน้อย 1 รูป (สูงสุด 5) รูปต้องเป็นของช่างเอง
    const noPhoto = await request('POST', `/orders/${order.id}/complete`, mechanic, undefined, 400);
    assert.ok(String(noPhoto.body.message).includes('กรุณาแนบรูปรถหลังซ่อมเสร็จอย่างน้อย 1 รูป'));
    await request('POST', `/orders/${order.id}/complete`, mechanic, { carPhotoUrls: [] }, 400);
    const car = await uploadImage(mechanic, 'ORDER');
    const receipt = await uploadImage(mechanic, 'ORDER');
    await request('POST', `/orders/${order.id}/complete`, mechanic, { carPhotoUrls: Array(6).fill(car) }, 400);
    const customerPhoto = await uploadImage(customer, 'ORDER');
    await request('POST', `/orders/${order.id}/complete`, mechanic, { carPhotoUrls: [customerPhoto] }, 400);
    await request(
      'POST',
      `/orders/${order.id}/complete`,
      mechanic,
      { carPhotoUrls: [car], receiptPhotoUrls: [receipt] },
      201,
    );
    const closed = (await request('GET', `/orders/${order.id}`, customer, undefined, 200)).body;
    assert.deepEqual(closed.closePhotos, [
      { kind: 'CAR', url: car },
      { kind: 'RECEIPT', url: receipt },
    ]);
    const history = (await request('GET', '/orders/mine', customer, undefined, 200)).body;
    assert.equal(history.find((o) => o.id === order.id).closePhotos.length, 2);
    const adminOrders = (await request('GET', '/admin/orders', staff, undefined, 200)).body;
    assert.equal(adminOrders.find((o) => o.id === order.id).closePhotos.length, 2);
    for (let i = 0; i < 2; i++)
      await request('POST', `/payments/orders/${order.id}/cash/confirm`, mechanic, undefined, 201);
    assert.equal((await request('GET', '/wallet/balance', mechanic, undefined, 200)).body.balance, -3500);
    assert.equal(await prisma.walletEntry.count({ where: { orderId: order.id } }), 1);
  });
  await check('Order chat is read-only after the job is completed', async () => {
    const chat = (await request('GET', `/orders/${order.id}/messages`, mechanic, undefined, 200)).body;
    assert.equal(chat.canSend, false);
    assert.equal(chat.messages.length, 3);
    const closed = await request('POST', `/orders/${order.id}/messages`, customer, { text: 'ขอบคุณครับ' }, 400);
    assert.equal(closed.body.message, 'งานนี้จบแล้ว แชทอ่านย้อนหลังได้อย่างเดียว');
  });
  await check('Rating is recorded once and customer cannot read wallet', async () => {
    await request('POST', `/orders/${order.id}/rate`, customer, { score: 5 }, 201);
    await request('POST', `/orders/${order.id}/rate`, customer, { score: 5 }, 400);
    await request('GET', '/wallet/balance', customer, undefined, 403);
  });
  await check('Second job completes through HTTP', async () => {
    secondOrder = (await request('POST', '/orders', customer, booking, 201)).body;
    await request('POST', `/dispatch/offers/${secondOrder.id}/accept`, mechanic, undefined, 201);
    await request('PATCH', `/orders/${secondOrder.id}/en-route`, mechanic, undefined, 200);
    await request('POST', `/orders/${secondOrder.id}/quote`, mechanic, { priceProposed: 10000 }, 201);
    const quote = (await request('GET', `/orders/${secondOrder.id}`, customer, undefined, 200)).body;
    await request(
      'POST',
      `/orders/${secondOrder.id}/quote/approve`,
      customer,
      { quoteVersion: quote.quoteVersion, priceProposed: 10000 },
      201,
    );
    await request('PATCH', `/orders/${secondOrder.id}/start`, mechanic, undefined, 200);
    await closeJob(mechanic, secondOrder.id, 201);
  });
  await check('Assigned mechanic sees customer phone only while the job is open', async () => {
    const open = (await request('POST', '/orders', customer, booking, 201)).body;
    await request('POST', `/dispatch/offers/${open.id}/accept`, mechanic, undefined, 201);
    const assigned = (await request('GET', '/orders/assigned', mechanic, undefined, 200)).body;
    assert.equal(assigned.find((item) => item.id === open.id).customer.phone, '0800000001');
    const done = assigned.find((item) => item.id === secondOrder.id);
    assert.equal(done.status, 'COMPLETED');
    assert.equal(done.customer, undefined);
    await request('POST', `/orders/${open.id}/cancel`, customer, undefined, 201);
    const after = (await request('GET', '/orders/assigned', mechanic, undefined, 200)).body;
    assert.equal(after.find((item) => item.id === open.id).customer, undefined);
  });
  await check('Payout info turns blanks into null and needs a bank account or PromptPay', async () => {
    const saved = (
      await request('PATCH', '/providers/me/payout-info', mechanic, { promptPayId: '' }, 200)
    ).body;
    assert.equal(saved.promptPayId, null);
    assert.equal(saved.bankAccountNumber, '1234567890');
    const rejected = await request(
      'PATCH',
      '/providers/me/payout-info',
      mechanic,
      { bankName: '', bankAccountName: null, bankAccountNumber: '', promptPayId: '' },
      400,
    );
    assert.match(JSON.stringify(rejected.body), /พร้อมเพย์/);
    assert.equal((await prisma.provider.findUnique({ where: { id: provider.id } })).bankName, 'Test bank');
  });
  await check('Signed image upload is write-once with correct content headers', async () => {
    slip = await uploadImage(customer, 'PAYMENT_SLIP');
  });
  await check('Manual QR and submitted slip are visible only to allowed actors', async () => {
    const qr = (await request('POST', `/payments/orders/${secondOrder.id}/promptpay`, customer, undefined, 201)).body;
    assert.match(qr.qrPayload, /^000201/);
    assert.equal(qr.promptPayId, '0800000099');
    await request('POST', `/payments/orders/${secondOrder.id}/slip`, stranger, { slipUrl: slip }, 400);
    const otherSlip = await uploadImage(stranger, 'PAYMENT_SLIP');
    await request('POST', `/payments/orders/${secondOrder.id}/slip`, stranger, { slipUrl: otherSlip }, 404);
    await request('POST', `/payments/orders/${secondOrder.id}/slip`, customer, { slipUrl: slip }, 201);
    const summary = (await request('GET', `/payments/orders/${secondOrder.id}`, mechanic, undefined, 200)).body;
    assert.equal(summary.slipUrl, undefined);
    await request('POST', `/admin/payments/${summary.id}/confirm`, staff, undefined, 403);
    await request('POST', `/admin/payments/${summary.id}/confirm`, owner, undefined, 201);
    await request('POST', `/admin/payments/${summary.id}/confirm`, owner, undefined, 201);
    assert.equal(await prisma.walletEntry.count({ where: { orderId: secondOrder.id } }), 1);
    assert.equal((await request('GET', '/wallet/balance', mechanic, undefined, 200)).body.balance, 3000);
  });
  await check('Withdrawal rejection refunds once and transfer deducts once', async () => {
    const first = (await request('POST', '/wallet/withdrawals', mechanic, { amount: 1000 }, 201)).body;
    await request('POST', `/admin/withdrawals/${first.id}/reject`, staff, {}, 403);
    await request('POST', `/admin/withdrawals/${first.id}/reject`, owner, {}, 201);
    await request('POST', `/admin/withdrawals/${first.id}/reject`, owner, {}, 400);
    assert.equal((await request('GET', '/wallet/balance', mechanic, undefined, 200)).body.balance, 3000);
    const second = (await request('POST', '/wallet/withdrawals', mechanic, { amount: 1000 }, 201)).body;
    await request('POST', `/admin/withdrawals/${second.id}/transferred`, owner, {}, 201);
    await request('POST', `/admin/withdrawals/${second.id}/transferred`, owner, {}, 400);
    assert.equal((await request('GET', '/wallet/balance', mechanic, undefined, 200)).body.balance, 2000);
    const entries = (await request('GET', '/wallet/entries', mechanic, undefined, 200)).body;
    assert.equal(entries.find((entry) => entry.withdrawalId === second.id).withdrawal.status, 'TRANSFERRED');
    await request('GET', '/admin/finance', owner, undefined, 200);
  });
  await check('Scheduled inspection stays unassigned and rejects invalid dates', async () => {
    const scheduled = {
      ...booking,
      categoryId: inspectionCategory.id,
      subServiceId: inspectionService.id,
      inspection: {
        brand: 'Test',
        appointmentAt: new Date(Date.now() + 2 * 3600000).toISOString(),
      },
    };
    const inspection = (await request('POST', '/orders', customer, scheduled, 201)).body;
    assert.equal(inspection.status, 'CREATED');
    assert.equal(inspection.providerId, null);
    await request('GET', `/orders/${inspection.id}/inspection`, customer, undefined, 200);
    await request('GET', `/orders/${inspection.id}/inspection`, stranger, undefined, 404);
    await request(
      'POST',
      '/orders',
      customer,
      {
        ...scheduled,
        inspection: { appointmentAt: new Date().toISOString() },
      },
      400,
    );
    await request('POST', `/orders/${inspection.id}/cancel`, customer, undefined, 201);
    assert.equal((await request('GET', `/orders/${inspection.id}`, customer, undefined, 200)).body.status, 'CANCELLED');
  });
  await check('Inspection requires evidence, hides drafts and locks the submitted report', async () => {
    const inspected = (
      await request(
        'POST',
        '/orders',
        customer,
        {
          ...booking,
          categoryId: inspectionCategory.id,
          subServiceId: inspectionService.id,
        },
        201,
      )
    ).body;
    await request('POST', `/dispatch/offers/${inspected.id}/accept`, mechanic, undefined, 201);
    await request('PATCH', `/orders/${inspected.id}/en-route`, mechanic, undefined, 200);
    await request('PATCH', `/orders/${inspected.id}/start`, mechanic, undefined, 200);
    await closeJob(mechanic, inspected.id, 400);
    await request('POST', `/orders/${inspected.id}/inspection/submit`, mechanic, undefined, 400);
    const checklist = (await request('GET', '/inspections/checklist', mechanic, undefined, 200)).body;
    const picture = await uploadImage(mechanic, 'INSPECTION');
    const items = checklist.sections
      .flatMap((section) => section.items)
      .filter((item) => !['electrified', 'manual'].includes(item.appliesTo))
      .map((item) => ({
        itemCode: item.code,
        status: 'PASS',
        ...(item.measurement
          ? {
              measurement: item.measurement.passMin ?? item.measurement.passMax,
            }
          : {}),
      }));
    await request(
      'PATCH',
      `/orders/${inspected.id}/inspection`,
      mechanic,
      {
        brand: 'Test',
        model: 'Test',
        year: 2020,
        plateNo: 'TEST',
        vin: 'TEST-VIN',
        mileageKm: 1000,
        powertrain: 'combustion',
        transmission: 'automatic',
        items,
        photoSlots: checklist.photoSlots
          .filter((slot) => slot.required)
          .map((slot) => ({
            slotCode: slot.code,
            photos: [{ url: picture }],
          })),
      },
      200,
    );
    assert.equal(
      (await request('GET', `/orders/${inspected.id}/inspection`, customer, undefined, 200)).body.items.length,
      0,
    );
    await request('POST', `/orders/${inspected.id}/inspection/submit`, mechanic, undefined, 201);
    const report = (await request('GET', `/orders/${inspected.id}/inspection`, customer, undefined, 200)).body;
    assert.ok(report.submittedAt);
    assert.equal(report.verdict, 'RECOMMENDED');
    assert.equal(report.items.length, items.length);
    await request('PATCH', `/orders/${inspected.id}/inspection`, mechanic, { summary: 'Cannot change' }, 400);
    await closeJob(mechanic, inspected.id, 201);
    await request('POST', `/payments/orders/${inspected.id}/cash/confirm`, mechanic, undefined, 201);
    await request('DELETE', '/account', mechanic, undefined, 409);
  });
  await check('Commission debt settlement credits once and is owner-only', async () => {
    const before = (await request('GET', '/wallet/debt', mechanic, undefined, 200)).body;
    assert.ok(before.owed > 0);
    const qr = (await request('GET', '/wallet/settlement-qr', mechanic, undefined, 200)).body;
    assert.equal(qr.amount, before.owed);
    const picture = await uploadImage(mechanic, 'PAYMENT_SLIP');
    const settlement = (await request('POST', '/wallet/settlements', mechanic, { slipUrl: picture }, 201)).body;
    await request('POST', `/admin/settlements/${settlement.id}/confirm`, staff, undefined, 403);
    await request('POST', `/admin/settlements/${settlement.id}/confirm`, owner, undefined, 201);
    await request('POST', `/admin/settlements/${settlement.id}/confirm`, owner, undefined, 201);
    assert.equal((await request('GET', '/wallet/balance', mechanic, undefined, 200)).body.balance, 0);
  });
  await check('Suspension blocks new offers and cancellation expires an offer', async () => {
    const pending = (await request('POST', '/orders', customer, booking, 201)).body;
    await request(
      'PATCH',
      `/admin/providers/${provider.id}/status`,
      owner,
      { status: 'SUSPENDED', note: 'Test suspension' },
      200,
    );
    await request('POST', `/dispatch/offers/${pending.id}/accept`, mechanic, undefined, 400);
    await request('POST', `/orders/${pending.id}/cancel`, customer, undefined, 201);
    assert.equal(
      await prisma.dispatchAttempt.count({
        where: { orderId: pending.id, status: 'OFFERED' },
      }),
      0,
    );
  });
  await check('Mechanic photos uploaded before registration do not expose the login phone', async () => {
    const phone = '0800000009';
    const applicant = await login(phone, 'PROVIDER');
    const photoUrl = await uploadImage(applicant, 'PROVIDER_TOOL');
    const toolUrl = await uploadImage(applicant, 'PROVIDER_TOOL');
    assert.ok(!photoUrl.includes(phone) && !toolUrl.includes(phone));
    const registered = (
      await request(
        'POST',
        '/providers/register',
        applicant,
        {
          realName: 'Photo privacy',
          nickname: 'Photo',
          experienceYears: 3,
          baseLat: 13.7,
          baseLng: 100.5,
          openMinute: 0,
          closeMinute: 1439,
          categoryIds: [category.id],
          vehicleTypeIds: [vehicle.id],
          toolPhotoUrls: [toolUrl],
          photoUrl,
          vehiclePlate: 'TEST 1',
        },
        201,
      )
    ).body;
    const stored = await prisma.provider.findUniqueOrThrow({
      where: { id: registered.provider.id },
      include: { toolPhotos: true },
    });
    assert.ok(!JSON.stringify(stored.photoUrl).includes(phone));
    assert.ok(stored.toolPhotos.every((tool) => !tool.url.includes(phone)));
  });
  await check('Admin closes a category: customers cannot see or book it until reopened', async () => {
    const catalog = (await request('GET', '/admin/catalog', staff, undefined, 200)).body;
    const row = catalog.find((item) => item.id === category.id);
    assert.ok(row && row.active && typeof row._count.providers === 'number');
    await request('PATCH', `/admin/catalog/categories/${category.id}`, customer, { active: false }, 403);
    await request('PATCH', `/admin/catalog/categories/${category.id}`, staff, { active: 'no' }, 400);
    await request('PATCH', `/admin/catalog/categories/${category.id}`, staff, { active: false }, 200);
    const visible = (await request('GET', '/catalog/categories', undefined, undefined, 200)).body;
    assert.ok(!visible.some((item) => item.id === category.id));
    await request('GET', `/catalog/categories/${category.id}/sub-services`, undefined, undefined, 404);
    const closed = await request('POST', '/orders', customer, booking, 400);
    assert.equal(closed.body.message, 'บริการนี้ปิดรับงานชั่วคราว กรุณาเลือกบริการอื่น');
    await request('PATCH', `/admin/catalog/categories/${category.id}`, staff, { active: true }, 200);

    // ปิดเฉพาะบริการย่อย
    await request('PATCH', `/admin/catalog/sub-services/${booking.subServiceId}`, owner, { active: false }, 200);
    const subs = (await request('GET', `/catalog/categories/${category.id}/sub-services`, undefined, undefined, 200)).body;
    assert.ok(!subs.some((item) => item.id === booking.subServiceId));
    await request('POST', '/orders', customer, booking, 400);
    await request('PATCH', `/admin/catalog/sub-services/${booking.subServiceId}`, owner, { active: true }, 200);
    assert.ok(
      (await auditCount({ action: { in: ['CATEGORY_ACTIVE', 'SUB_SERVICE_ACTIVE'] } }, 4)) >= 4,
    );
  });
  await check('Mechanic changes job hours any time; invalid minutes are rejected', async () => {
    const bangkok = new Date(Date.now() + 7 * 60 * 60 * 1000);
    const nowMinute = bangkok.getUTCHours() * 60 + bangkok.getUTCMinutes();
    // ช่วง 1 นาทีที่ห่างจากตอนนี้ 12 ชม. = ตอนนี้นอกเวลารับงาน
    const away = (nowMinute + 720) % 1440;
    const hours = (
      await request('PATCH', '/providers/me/hours', mechanic, { openMinute: away, closeMinute: away }, 200)
    ).body;
    assert.deepEqual(hours, { openMinute: away, closeMinute: away });
    assert.equal((await request('GET', '/providers/me', mechanic, undefined, 200)).body.openMinute, away);
    await request('PATCH', '/providers/me/hours', mechanic, { openMinute: 1440, closeMinute: 0 }, 400);
    await request('PATCH', '/providers/me/hours', mechanic, { openMinute: -1, closeMinute: 0 }, 400);
    await request('PATCH', '/providers/me/hours', mechanic, { openMinute: 1.5, closeMinute: 0 }, 400);
    await request('PATCH', '/providers/me/hours', customer, { openMinute: 0, closeMinute: 1439 }, 403);
    // กลับเป็นตลอดเวลา
    await request('PATCH', '/providers/me/hours', mechanic, { openMinute: 0, closeMinute: 1439 }, 200);
  });
  await check('A stale pending LINE session switches to the account registered elsewhere', async () => {
    const stale = pendingLineToken('Usmoke-refresh');
    await request('POST', '/auth/line/refresh', stale, undefined, 404);
    const photoUrl = await uploadImage(stale, 'PROVIDER_TOOL');
    const form = {
      realName: 'Line refresh',
      nickname: 'Refresh',
      experienceYears: 2,
      baseLat: 13.7,
      baseLng: 100.5,
      openMinute: 0,
      closeMinute: 1439,
      categoryIds: [category.id],
      vehicleTypeIds: [vehicle.id],
      toolPhotoUrls: [photoUrl],
      photoUrl,
      vehiclePlate: 'TEST 2',
      phone: '0800000010',
    };
    const registered = (await request('POST', '/providers/register', stale, form, 201)).body;
    // เบราว์เซอร์อื่นยังถือ pending token เดิม: ส่งซ้ำได้ 409 แล้วแลกเป็นโทเคนบัญชีจริง
    const again = await request('POST', '/providers/register', stale, form, 409);
    assert.equal(again.body.message, 'บัญชีนี้สมัครแล้ว กรุณาเข้าสู่ระบบใหม่');
    await request('GET', '/providers/me', stale, undefined, 404);
    const session = (await request('POST', '/auth/line/refresh', stale, undefined, 201)).body;
    assert.equal(session.hasProfile, true);
    assert.equal(session.userId, registered.provider.id);
    const me = (await request('GET', '/providers/me', session.accessToken, undefined, 200)).body;
    assert.equal(me.id, registered.provider.id);
    // ใช้ได้เฉพาะ pending token ของ LINE
    await request('POST', '/auth/line/refresh', session.accessToken, undefined, 403);
    await request('POST', '/auth/line/refresh', await login('0800000011', 'PROVIDER'), undefined, 403);
    await request('POST', '/auth/line/refresh', undefined, undefined, 401);
  });
  await check('Account deletion removes profile access and admin actions leave an audit trail', async () => {
    await request('DELETE', '/account', mechanic, undefined, 200);
    await request('GET', '/providers/me', mechanic, undefined, 401);
    assert.ok((await prisma.adminAuditLog.count()) > 0);
  });
  console.log(`HTTP smoke: ${passed} scenarios passed (no real SMS, LINE, push or money transfer).`);
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(async () => {
    if (api && api.exitCode === null) {
      api.kill('SIGTERM');
      await Promise.race([new Promise((resolve) => api.once('exit', resolve)), delay(5000)]);
      if (api.exitCode === null) api.kill('SIGKILL');
    }
    await prisma.$disconnect();
    if (uploads) await rm(uploads, { recursive: true, force: true });
  });
