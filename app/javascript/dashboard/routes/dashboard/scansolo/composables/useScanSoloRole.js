import { computed } from 'vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store.js';

// RF-48 / D-18: the role checks every ScanSolo screen shares. The server
// policies stay the source of truth; this only decides what to render.
export function useScanSoloRole() {
  const { isAdmin } = useAdmin();
  const currentUser = useMapGetter('getCurrentUser');

  const isAdministrator = computed(() => isAdmin.value);
  const isOwner = ownerId =>
    ownerId !== null &&
    ownerId !== undefined &&
    ownerId === currentUser.value?.id;

  return { isAdministrator, isOwner };
}
