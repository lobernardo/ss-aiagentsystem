<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import EmptyStateLayout from 'dashboard/components-next/EmptyStateLayout.vue';

const props = defineProps({
  moduleKey: {
    type: String,
    required: true,
  },
});

const { t } = useI18n();

const i18nKey = computed(() => props.moduleKey.toUpperCase());
const title = computed(() => t(`SCANSOLO.MODULES.${i18nKey.value}.TITLE`));
const subtitle = computed(() =>
  t(`SCANSOLO.MODULES.${i18nKey.value}.DESCRIPTION`)
);
</script>

<template>
  <EmptyStateLayout
    :title="title"
    :subtitle="subtitle"
    :show-backdrop="false"
  />
</template>
