import { computed } from 'vue';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useMapGetter } from 'dashboard/composables/store.js';

// RF-48 / D-18: the role checks every ScanSolo screen shares. The server
// policies stay the source of truth; this only decides what to render.
export function useScanSoloRole() {
  const { isAdmin } = useAdmin();
  const currentUser = useMapGetter('getCurrentUser');

  const isAdministrator = computed(() => isAdmin.value);
  const isCurrentUser = userId =>
    userId !== null && userId !== undefined && userId === currentUser.value?.id;
  const isOwner = isCurrentUser;
  // CT-02: `commercialUserId` comes from the published agent config.
  const isCommercialUser = isCurrentUser;
  // CT-02 / CT-03: administrators or the published commercial user approve,
  // reject and retry proposals.
  const canApproveProposals = commercialUserId =>
    isAdministrator.value || isCommercialUser(commercialUserId);

  return { isAdministrator, isOwner, isCommercialUser, canApproveProposals };
}
