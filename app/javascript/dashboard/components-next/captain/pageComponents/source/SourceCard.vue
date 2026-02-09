<script setup>
import { computed } from 'vue';
import { useToggle } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { usePolicy } from 'dashboard/composables/usePolicy';

import CardLayout from 'dashboard/components-next/CardLayout.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  id: { type: Number, required: true },
  title: { type: String, default: '' },
  sourceType: { type: String, required: true },
  externalLink: { type: String, default: '' },
  status: { type: String, default: 'pending' },
  createdAt: { type: Number, required: true },
});

const emit = defineEmits(['action']);
const { checkPermissions } = usePolicy();
const { t } = useI18n();
const [showActionsDropdown, toggleDropdown] = useToggle();

const sourceTypeLabel = computed(() => {
  const labels = {
    web_url: t('CAPTAIN.SOURCES.SOURCE_TYPES.WEB_URL'),
    pdf: t('CAPTAIN.SOURCES.SOURCE_TYPES.PDF'),
    private_article: t('CAPTAIN.SOURCES.SOURCE_TYPES.PRIVATE_ARTICLE'),
  };
  return labels[props.sourceType] || props.sourceType;
});

const sourceTypeIcon = computed(() => {
  const icons = {
    web_url: 'i-ph-globe-duotone',
    pdf: 'i-ph-file-pdf-duotone',
    private_article: 'i-ph-article-duotone',
  };
  return icons[props.sourceType] || 'i-ph-file-duotone';
});

const statusBadgeClass = computed(() => {
  const classMap = {
    pending: 'bg-n-amber-3 text-n-amber-11',
    processing: 'bg-n-blue-3 text-n-blue-11',
    active: 'bg-n-green-3 text-n-green-11',
    failed: 'bg-n-ruby-3 text-n-ruby-11',
  };
  return classMap[props.status] || 'bg-n-slate-3 text-n-slate-11';
});

const statusLabel = computed(() => {
  const labels = {
    pending: t('CAPTAIN.SOURCES.STATUS.PENDING'),
    processing: t('CAPTAIN.SOURCES.STATUS.PROCESSING'),
    active: t('CAPTAIN.SOURCES.STATUS.ACTIVE'),
    failed: t('CAPTAIN.SOURCES.STATUS.FAILED'),
  };
  return labels[props.status] || props.status;
});

const menuItems = computed(() => {
  const items = [];
  if (props.sourceType === 'private_article') {
    items.push({
      label: t('CAPTAIN.SOURCES.OPTIONS.EDIT_SOURCE'),
      value: 'edit',
      action: 'edit',
      icon: 'i-lucide-pencil',
    });
  }
  if (props.sourceType === 'web_url' || props.sourceType === 'pdf') {
    items.push({
      label: t('CAPTAIN.SOURCES.OPTIONS.RECRAWL_SOURCE'),
      value: 'recrawl',
      action: 'recrawl',
      icon: 'i-lucide-refresh-cw',
    });
  }
  if (checkPermissions(['administrator'])) {
    items.push({
      label: t('CAPTAIN.SOURCES.OPTIONS.DELETE_SOURCE'),
      value: 'delete',
      action: 'delete',
      icon: 'i-lucide-trash',
    });
  }
  return items;
});

const createdAt = computed(() => dynamicTime(props.createdAt));

const showLink = computed(() => {
  return props.externalLink && !props.externalLink.startsWith('PDF:');
});

const handleAction = ({ action, value }) => {
  toggleDropdown(false);
  emit('action', { action, value, id: props.id });
};
</script>

<template>
  <CardLayout>
    <div class="flex gap-1 justify-between w-full">
      <div class="flex gap-2 items-center min-w-0">
        <i :class="sourceTypeIcon" class="text-lg shrink-0 text-n-slate-11" />
        <span class="text-base text-n-slate-12 line-clamp-1">
          {{ title }}
        </span>
      </div>
      <div class="flex gap-2 items-center shrink-0">
        <span
          :class="statusBadgeClass"
          class="px-2 py-0.5 text-xs font-medium rounded-full"
        >
          {{ statusLabel }}
        </span>
        <div
          v-on-clickaway="() => toggleDropdown(false)"
          class="flex relative items-center group"
        >
          <Button
            icon="i-lucide-ellipsis-vertical"
            color="slate"
            size="xs"
            class="rounded-md group-hover:bg-n-alpha-2"
            @click="toggleDropdown()"
          />
          <DropdownMenu
            v-if="showActionsDropdown"
            :menu-items="menuItems"
            class="top-full mt-1 ltr:right-0 rtl:left-0"
            @action="handleAction($event)"
          />
        </div>
      </div>
    </div>
    <div class="flex gap-4 justify-between items-center w-full">
      <span class="flex gap-1 items-center text-sm shrink-0 text-n-slate-11">
        {{ sourceTypeLabel }}
      </span>
      <span
        v-if="showLink"
        class="flex flex-1 gap-1 justify-start items-center text-sm truncate text-n-slate-11"
      >
        <i class="i-ph-link-simple shrink-0" />
        <span class="truncate">{{ externalLink }}</span>
      </span>
      <div class="text-sm shrink-0 text-n-slate-11 line-clamp-1">
        {{ createdAt }}
      </div>
    </div>
  </CardLayout>
</template>
