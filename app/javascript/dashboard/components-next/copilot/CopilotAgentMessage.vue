<script setup>
defineProps({
  message: {
    type: Object,
    required: true,
  },
});
</script>

<template>
  <div class="space-y-1 text-n-slate-12">
    <div class="break-words text-n-slate-11 bg-n-alpha-2 rounded-lg px-3 py-2">
      {{ message.content }}
    </div>
  </div>
</template>
