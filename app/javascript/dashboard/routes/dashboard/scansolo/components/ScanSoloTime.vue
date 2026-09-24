<script setup>
import { computed } from 'vue';
import { dynamicTime, messageStamp } from 'shared/helpers/timeHelper';

// UI-10: relative time with the absolute date on hover, through the native
// time helpers. The raw ISO value is never written to the DOM.
const props = defineProps({
  value: { type: String, default: null },
  fallback: { type: String, default: '' },
});

const ABSOLUTE_FORMAT = 'dd/MM/yyyy HH:mm';

const unixTime = computed(() =>
  props.value ? Math.floor(new Date(props.value).getTime() / 1000) : null
);
</script>

<template>
  <span
    v-if="unixTime"
    data-testid="scansolo-time"
    :title="messageStamp(unixTime, ABSOLUTE_FORMAT)"
  >
    {{ dynamicTime(unixTime) }}
  </span>
  <span v-else>{{ fallback }}</span>
</template>
