import {
  BadRequestException,
  ExecutionContext,
  ForbiddenException,
  UnauthorizedException,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AdminRole } from '@prisma/client';

import { AdminAccessGuard, OwnerOnly } from './admin-access';
import { AdminController } from './admin.controller';
import { AdminService } from './admin.service';

function contextFor(handler: (...args: never[]) => unknown, sub = 'a1') {
  const request: Record<string, unknown> = { user: { sub } };
  return {
    request,
    context: {
      getHandler: () => handler,
      getClass: () => AdminController,
      switchToHttp: () => ({ getRequest: () => request }),
    } as unknown as ExecutionContext,
  };
}

describe('AdminAccessGuard', () => {
  class Handlers {
    @OwnerOnly()
    money() {}
    daily() {}
  }
  const handlers = new Handlers();

  function guardWith(admin: Record<string, unknown> | null) {
    const prisma = {
      adminUser: { findUnique: jest.fn().mockResolvedValue(admin) },
    };
    return new AdminAccessGuard(prisma as never, new Reflector());
  }

  it('lets staff use daily operations and attaches the admin', async () => {
    const staff = { id: 'a1', role: AdminRole.STAFF, disabledAt: null };
    const { context, request } = contextFor(handlers.daily);
    await expect(guardWith(staff).canActivate(context)).resolves.toBe(true);
    expect(request.admin).toBe(staff);
  });

  it('keeps money actions for the owner', async () => {
    const staff = { id: 'a1', role: AdminRole.STAFF, disabledAt: null };
    await expect(
      guardWith(staff).canActivate(contextFor(handlers.money).context),
    ).rejects.toBeInstanceOf(ForbiddenException);
    const owner = { id: 'a1', role: AdminRole.OWNER, disabledAt: null };
    await expect(
      guardWith(owner).canActivate(contextFor(handlers.money).context),
    ).resolves.toBe(true);
  });

  it('rejects a disabled or deleted admin even with a valid token', async () => {
    const disabled = {
      id: 'a1',
      role: AdminRole.OWNER,
      disabledAt: new Date(),
    };
    await expect(
      guardWith(disabled).canActivate(contextFor(handlers.daily).context),
    ).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(
      guardWith(null).canActivate(contextFor(handlers.daily).context),
    ).rejects.toBeInstanceOf(UnauthorizedException);
  });
});

describe('money endpoints are owner-only', () => {
  const reflector = new Reflector();
  const proto = AdminController.prototype as unknown as Record<
    string,
    (...args: never[]) => unknown
  >;
  it.each([
    'confirmSlip',
    'rejectSlip',
    'financeReport',
    'confirmSettlement',
    'rejectSettlement',
    'markTransferred',
    'reject',
    'listAdmins',
    'createAdmin',
    'updateAdmin',
    'listAudit',
  ])('%s', (name) => {
    expect(reflector.get('admin:owner-only', proto[name])).toBe(true);
  });

  it.each(['setProviderStatus', 'redispatch', 'cancelOrder', 'listSlips'])(
    '%s stays open to staff',
    (name) => {
      expect(reflector.get('admin:owner-only', proto[name])).toBeUndefined();
    },
  );
});

describe('AdminService.updateAdmin', () => {
  function serviceWith(target: Record<string, unknown>, activeOwners = 2) {
    const prisma = {
      adminUser: {
        findUnique: jest.fn().mockResolvedValue(target),
        count: jest.fn().mockResolvedValue(activeOwners),
        update: jest.fn(({ data }) => ({ ...target, ...data })),
      },
    };
    const service = new AdminService(
      prisma as never,
      {} as never,
      {} as never,
      {} as never,
      {} as never,
      { record: jest.fn() } as never,
    );
    return { service, prisma };
  }
  const owner = { id: 'o1', role: AdminRole.OWNER, disabledAt: null };

  it('does not let an admin disable or demote themselves', async () => {
    const { service } = serviceWith(owner);
    await expect(
      service.updateAdmin('o1', 'o1', { disabled: true }),
    ).rejects.toBeInstanceOf(BadRequestException);
    await expect(
      service.updateAdmin('o1', 'o1', { role: AdminRole.STAFF }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('always keeps one active owner', async () => {
    const { service } = serviceWith(owner, 1);
    await expect(
      service.updateAdmin('o2', 'o1', { disabled: true }),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('disables staff and hashes a new password', async () => {
    const staff = { id: 's1', role: AdminRole.STAFF, disabledAt: null };
    const { service, prisma } = serviceWith(staff);
    await service.updateAdmin('o1', 's1', {
      disabled: true,
      password: 'new-password-123',
    });
    const data = prisma.adminUser.update.mock.calls[0][0].data;
    expect(data.disabledAt).toBeInstanceOf(Date);
    expect(data.passwordHash).toBeDefined();
    expect(data.passwordHash).not.toContain('new-password-123');
  });
});
