import { computed, ref } from 'vue';
import { shallowMount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import Sidebar from '../Sidebar.vue';
import SidebarGroup from '../SidebarGroup.vue';
import { SCANSOLO_MODULES } from 'dashboard/routes/dashboard/scansolo/scansoloModules';

const currentAccount = ref({ id: 1 });

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    accountScopedRoute: name => ({ name, params: { accountId: 1 } }),
    isOnChatwootCloud: ref(false),
    currentAccount,
  }),
}));
vi.mock('dashboard/composables/useConfig', () => ({
  useConfig: () => ({ isEnterprise: false }),
}));
vi.mock('vuex', () => ({ useStore: () => ({ dispatch: vi.fn() }) }));
vi.mock('dashboard/composables/store', () => ({
  // Lookup getters take an id; list getters return arrays; the rest are flags.
  useMapGetter: key =>
    computed(() => {
      if (/get(Inbox|Label|Team|Folder)UnreadCount$/.test(key)) return () => 0;
      if (key.endsWith('isFeatureEnabledonAccount')) return () => false;
      if (key.endsWith('getSectionSort')) return () => undefined;
      if (/getInboxes|getLabelsOnSidebar|getMyTeams|CustomViews$/.test(key)) {
        return [];
      }
      return 0;
    }),
}));
vi.mock('../provider', () => ({
  provideSidebarContext: vi.fn(),
  useSidebarResize: () => ({
    sidebarWidth: ref(200),
    isCollapsed: computed(() => false),
    setSidebarWidth: vi.fn(),
    saveWidth: vi.fn(),
    snapToCollapsed: vi.fn(),
    snapToExpanded: vi.fn(),
  }),
}));
vi.mock('../useSidebarKeyboardShortcuts', () => ({
  useSidebarKeyboardShortcuts: vi.fn(),
}));

const i18n = createI18n({
  legacy: false,
  locale: 'en',
  messages: {},
  missingWarn: false,
  fallbackWarn: false,
});

// Same props as the real group, so the menu items arrive as props.
const SidebarGroupStub = {
  name: 'SidebarGroup',
  props: SidebarGroup.props,
  render: () => null,
};

const menuNames = wrapper =>
  wrapper
    .findAllComponents({ name: 'SidebarGroup' })
    .map(group => group.props('name'));

const mountSidebar = () =>
  shallowMount(Sidebar, {
    global: {
      plugins: [i18n],
      directives: { onClickOutside: {} },
      stubs: { SidebarGroup: SidebarGroupStub, RouterLink: true },
    },
  });

describe('Sidebar menu order', () => {
  it('puts the ScanSolo group first, before every native item', () => {
    currentAccount.value = { id: 1, scansolo_enabled: true };

    const wrapper = mountSidebar();
    const names = menuNames(wrapper);

    expect(names[0]).toBe('ScanSolo');
    expect(names.slice(1, 3)).toEqual(['Inbox', 'Conversation']);
    expect(names).toEqual(expect.arrayContaining(['Contacts', 'Settings']));

    const scanSolo = wrapper.findAllComponents({ name: 'SidebarGroup' })[0];
    // No own `to`: the group header opens its first child, the Pipeline.
    expect(scanSolo.props('to')).toBeNull();
    expect(scanSolo.props('children').map(child => child.to.name)).toEqual(
      SCANSOLO_MODULES.map(scanSoloModule => scanSoloModule.name)
    );
    expect(scanSolo.props('children')[0].to.name).toBe(
      'scansolo_pipeline_index'
    );
  });

  it('keeps the native order without the ScanSolo group on other accounts', () => {
    currentAccount.value = { id: 1, scansolo_enabled: false };

    const names = menuNames(mountSidebar());

    expect(names).not.toContain('ScanSolo');
    expect(names.slice(0, 2)).toEqual(['Inbox', 'Conversation']);
  });
});
