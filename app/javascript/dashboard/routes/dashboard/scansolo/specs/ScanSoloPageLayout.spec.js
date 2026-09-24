import { mount } from '@vue/test-utils';
import ScanSoloPageLayout from '../components/ScanSoloPageLayout.vue';
import scansoloRoutes from '../index';

vi.mock('dashboard/store', () => ({
  default: { getters: {}, dispatch: vi.fn() },
}));

const sources = import.meta.glob('../**/*.vue', {
  query: '?raw',
  import: 'default',
  eager: true,
});

const components = import.meta.glob('../**/*.vue', {
  import: 'default',
  eager: true,
});

const templateRoot = source =>
  source
    .split('<template>')[1]
    .split('\n')
    .find(line => line.trim())
    .trim();

describe('ScanSoloPageLayout', () => {
  it('renders the slot inside a bounded vertical scroll container', () => {
    const wrapper = mount(ScanSoloPageLayout, {
      slots: { default: '<button data-testid="save">Save</button>' },
    });
    const scroll = wrapper.find('[data-testid="scansolo-page-scroll"]');

    expect(wrapper.classes()).toEqual(
      expect.arrayContaining(['flex', 'flex-col', 'h-full', 'min-h-0'])
    );
    expect(scroll.classes()).toEqual(
      expect.arrayContaining(['flex-1', 'min-h-0', 'overflow-y-auto'])
    );
    expect(scroll.find('[data-testid="save"]').exists()).toBe(true);
  });

  it.each(scansoloRoutes.routes.map(route => [route.name, route.component]))(
    '%s renders its root inside the layout',
    (_name, component) => {
      const file = Object.keys(components).find(
        path => components[path] === component
      );

      expect(file).toBeDefined();
      expect(templateRoot(sources[file])).toBe('<ScanSoloPageLayout>');
    }
  );
});
