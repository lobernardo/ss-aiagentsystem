import { test, expect, APIRequestContext } from '@playwright/test';
import { Login } from '@components/ui';

// UI-06, UI-08, RNF-11 (scansolo-proposta-aprovacao-email): after "Assumir
// conversa" the agent opens another conversation straight from the list,
// closes it with the X and comes back to the first one still in human
// control -- and none of that navigation touches ai_control_state, assignee
// or status of either conversation.
//
// Preconditions on the stack under test: SCANSOLO_ACCOUNT_ID is an account
// with `scansolo_enabled` (no public API flips that flag), and
// API_ACCESS_TOKEN belongs to TEST_USER_EMAIL, an administrator of it.

const TEST_EMAIL = process.env.TEST_USER_EMAIL || 'admin@chatwoot.com';
const TEST_PASSWORD = process.env.TEST_USER_PASSWORD || 'Password123@#';
const API_ACCESS_TOKEN = process.env.API_ACCESS_TOKEN || '';
const ACCOUNT_ID = Number(process.env.SCANSOLO_ACCOUNT_ID || 1);

const AI_ACTIVE_LABEL = 'IA respondendo automaticamente';
const HUMAN_ACTIVE_LABEL = 'Atendimento humano em andamento';
const TAKEOVER_LABEL = 'Assumir conversa';

type ConversationSnapshot = {
  aiControlState: string;
  assigneeId: number | null;
  status: string;
};

const accountPath = (path: string) => `/api/v1/accounts/${ACCOUNT_ID}${path}`;

const apiCall = async (
  api: APIRequestContext,
  method: 'get' | 'post' | 'put' | 'delete',
  path: string,
  data?: object
) => {
  const response = await api[method](accountPath(path), { data });
  expect(response.ok(), `${method.toUpperCase()} ${path}`).toBe(true);
  const body = await response.text();
  return body ? JSON.parse(body) : {};
};

const snapshot = async (
  api: APIRequestContext,
  conversationId: number
): Promise<ConversationSnapshot> => {
  const control = await apiCall(
    api,
    'get',
    `/scan_solo/conversations/${conversationId}/control_state`
  );
  const conversation = await apiCall(
    api,
    'get',
    `/conversations/${conversationId}`
  );
  return {
    aiControlState: control.ai_control_state,
    assigneeId: conversation.meta.assignee?.id ?? null,
    status: conversation.status,
  };
};

test.describe('ScanSolo handoff - takeover and conversation navigation', () => {
  let api: APIRequestContext;
  let adminId: number;
  let inboxId: number;
  let leads: { name: string; conversationId: number }[] = [];

  test.beforeAll(async ({ playwright, baseURL }) => {
    api = await playwright.request.newContext({
      baseURL,
      extraHTTPHeaders: { api_access_token: API_ACCESS_TOKEN },
    });

    const profileResponse = await api.get('/api/v1/profile');
    expect(profileResponse.ok()).toBe(true);
    adminId = (await profileResponse.json()).id;

    const inbox = await apiCall(api, 'post', '/inboxes', {
      name: `ScanSolo E2E ${Date.now()}`,
      channel: { type: 'api' },
    });
    inboxId = inbox.id;

    await apiCall(api, 'put', '/scan_solo/ai_agent_config/draft', {
      enabled: true,
      allowed_inbox_ids: [inboxId],
    });
    await apiCall(api, 'post', '/scan_solo/ai_agent_config/publish');
  });

  test.beforeEach(async () => {
    const stamp = Date.now();
    leads = [];

    for (const name of [`Lead IA ${stamp}`, `Lead Outro ${stamp}`]) {
      const contact = await apiCall(api, 'post', '/contacts', { name });
      const conversation = await apiCall(api, 'post', '/conversations', {
        inbox_id: inboxId,
        contact_id: contact.payload.contact.id,
        assignee_id: adminId,
        status: 'open',
      });
      leads.push({ name, conversationId: conversation.id });
    }
  });

  // Conversation and inbox deletion run in background jobs. Contacts are kept:
  // deleting one destroys its conversations asynchronously too, and until that
  // job runs the orphaned conversations break the conversation list.
  test.afterEach(async () => {
    for (const lead of leads) {
      await apiCall(api, 'delete', `/conversations/${lead.conversationId}`);
    }
  });

  test.afterAll(async () => {
    await apiCall(api, 'delete', `/inboxes/${inboxId}`);
    await api.dispose();
  });

  test('keeps human control after switching conversations and closing the panel', async ({
    page,
  }) => {
    const [first, second] = leads;
    const firstId = first.conversationId;
    const secondId = second.conversationId;
    const conversationUrl = (id: number) =>
      new RegExp(`/app/accounts/${ACCOUNT_ID}/conversations/${id}$`);
    const listCard = (name: string) =>
      page.locator('.conversation').filter({ hasText: name });

    expect((await snapshot(api, firstId)).aiControlState).toBe('ai_active');

    const login = new Login(page);
    await login.navigate();
    await login.login(TEST_EMAIL, TEST_PASSWORD);
    await page.waitForURL(/\/app\/accounts\/\d+\//);

    await page.goto(`/app/accounts/${ACCOUNT_ID}/conversations/${firstId}`);
    const stateLabel = page.getByTestId('control-state-label');
    await expect(stateLabel).toHaveText(AI_ACTIVE_LABEL);

    await page.getByTestId('takeover-button').click();
    const reasonDialog = page.locator('dialog[open]');
    await reasonDialog
      .getByTestId('takeover-reason-input')
      .fill('Cliente pediu atendimento humano');
    await reasonDialog.getByRole('button', { name: TAKEOVER_LABEL }).click();
    await expect(reasonDialog).toHaveCount(0);
    await expect(stateLabel).toHaveText(HUMAN_ACTIVE_LABEL);

    const before = {
      first: await snapshot(api, firstId),
      second: await snapshot(api, secondId),
    };
    expect(before.first).toEqual({
      aiControlState: 'human_active',
      assigneeId: adminId,
      status: 'open',
    });
    expect(before.second).toEqual({
      aiControlState: 'ai_active',
      assigneeId: adminId,
      status: 'open',
    });

    // UI-06: the second conversation opens straight from the list.
    await listCard(second.name).click();
    await expect(page).toHaveURL(conversationUrl(secondId));
    await expect(stateLabel).toHaveText(AI_ACTIVE_LABEL);

    // The X only closes the panel and goes back to the list.
    await page.getByTestId('conversation-close-button').click();
    await expect(page).not.toHaveURL(/\/conversations\/\d+$/);

    await listCard(first.name).click();
    await expect(page).toHaveURL(conversationUrl(firstId));
    await expect(stateLabel).toHaveText(HUMAN_ACTIVE_LABEL);

    // UI-08: navigating and closing never changed control, assignee or status.
    expect({
      first: await snapshot(api, firstId),
      second: await snapshot(api, secondId),
    }).toEqual(before);
  });
});
