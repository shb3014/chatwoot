<script setup>
import {
  computed,
  onMounted,
  onBeforeUnmount,
  ref,
  nextTick,
  watch,
} from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import { debounce } from '@chatwoot/utils';
import { frontendURL } from 'dashboard/helper/URLHelper';

import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

import DeleteDialog from 'dashboard/components-next/captain/pageComponents/DeleteDialog.vue';
import SourceCard from 'dashboard/components-next/captain/pageComponents/source/SourceCard.vue';
import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import CaptainPaywall from 'dashboard/components-next/captain/pageComponents/Paywall.vue';
import CreateSourceDialog from 'dashboard/components-next/captain/pageComponents/source/CreateSourceDialog.vue';
import FeatureSpotlightPopover from 'dashboard/components-next/feature-spotlight/FeatureSpotlightPopover.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();
const { accountId } = useAccount();

const uiFlags = useMapGetter('captainSources/getUIFlags');
const sources = useMapGetter('captainSources/getRecords');
const isFetching = computed(() => uiFlags.value.fetchingList);
const sourcesMeta = useMapGetter('captainSources/getMeta');

const selectedSourceType = ref('all');
const searchQuery = ref('');
const selectedSource = ref(null);
const deleteSourceDialog = ref(null);
const showCreateDialog = ref(false);
const createSourceDialog = ref(null);

const sourceTypeOptions = computed(() => [
  { value: 'all', label: 'All' },
  { value: 'web_url', label: 'Web URL' },
  { value: 'pdf', label: 'PDF' },
  { value: 'private_article', label: 'Article' },
]);

const fetchSources = (page = 1) => {
  const filterParams = { page };
  if (selectedSourceType.value !== 'all') {
    filterParams.sourceType = selectedSourceType.value;
  }
  if (searchQuery.value) {
    filterParams.search = searchQuery.value;
  }
  store.dispatch('captainSources/get', filterParams);
};

const debouncedSearch = debounce(() => fetchSources(), 500, false);

const handleSourceTypeChange = type => {
  selectedSourceType.value = type;
  fetchSources();
};

const handleSearchInput = () => {
  debouncedSearch();
};

const handleCreateSource = () => {
  showCreateDialog.value = true;
  nextTick(() => createSourceDialog.value.dialogRef.open());
};

const handleCreateDialogClose = () => {
  showCreateDialog.value = false;
};

const handleDelete = () => {
  deleteSourceDialog.value.dialogRef.open();
};

const handleRecrawl = async id => {
  try {
    await store.dispatch('captainSources/recrawl', id);
    useAlert(t('CAPTAIN.SOURCES.RECRAWL.SUCCESS_MESSAGE'));
    fetchSources();
  } catch (error) {
    useAlert(t('CAPTAIN.SOURCES.RECRAWL.ERROR_MESSAGE'));
  }
};

const handleAction = ({ action, id }) => {
  selectedSource.value = sources.value.find(s => id === s.id);

  nextTick(() => {
    if (action === 'delete') {
      handleDelete();
    } else if (action === 'edit') {
      router.push(
        frontendURL(`accounts/${accountId.value}/captain/sources/${id}/edit`)
      );
    } else if (action === 'recrawl') {
      handleRecrawl(id);
    }
  });
};

const onPageChange = page => fetchSources(page);

const onDeleteSuccess = () => {
  if (sources.value?.length === 0 && sourcesMeta.value?.page > 1) {
    onPageChange(sourcesMeta.value.page - 1);
  }
};

// Auto-polling: re-fetch sources when any are pending or processing
const POLL_INTERVAL_MS = 5000;
let pollTimer = null;

const hasPendingSources = computed(() =>
  sources.value.some(s => s.status === 'pending' || s.status === 'processing')
);

const startPolling = () => {
  if (pollTimer) return;
  pollTimer = setInterval(() => {
    fetchSources(sourcesMeta.value?.page || 1);
  }, POLL_INTERVAL_MS);
};

const stopPolling = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

watch(hasPendingSources, shouldPoll => {
  if (shouldPoll) {
    startPolling();
  } else {
    stopPolling();
  }
});

onMounted(() => {
  fetchSources();
});

onBeforeUnmount(() => {
  stopPolling();
});
</script>

<template>
  <PageLayout
    :header-title="$t('CAPTAIN.SOURCES.HEADER')"
    :button-label="$t('CAPTAIN.SOURCES.ADD_NEW')"
    :button-policy="['administrator']"
    :total-count="sourcesMeta.totalCount"
    :current-page="sourcesMeta.page"
    :show-pagination-footer="!isFetching && !!sources.length"
    :is-fetching="isFetching"
    :is-empty="!sources.length"
    :feature-flag="FEATURE_FLAGS.CAPTAIN"
    @update:current-page="onPageChange"
    @click="handleCreateSource"
  >
    <template #knowMore>
      <FeatureSpotlightPopover
        :button-label="$t('CAPTAIN.HEADER_KNOW_MORE')"
        :title="$t('CAPTAIN.SOURCES.EMPTY_STATE.FEATURE_SPOTLIGHT.TITLE')"
        :note="$t('CAPTAIN.SOURCES.EMPTY_STATE.FEATURE_SPOTLIGHT.NOTE')"
      />
    </template>

    <template #emptyState>
      <div class="flex flex-col items-center justify-center py-16 gap-4">
        <div
          class="flex justify-center items-center w-16 h-16 rounded-2xl bg-n-slate-3"
        >
          <i class="text-3xl i-ph-database-duotone text-n-slate-11" />
        </div>
        <h3 class="text-lg font-medium text-n-slate-12">
          {{ $t('CAPTAIN.SOURCES.EMPTY_STATE.TITLE') }}
        </h3>
        <p class="max-w-md text-sm text-center text-n-slate-11">
          {{ $t('CAPTAIN.SOURCES.EMPTY_STATE.SUBTITLE') }}
        </p>
      </div>
    </template>

    <template #paywall>
      <CaptainPaywall />
    </template>

    <template #controls>
      <div class="mb-4 -mt-3 flex gap-3">
        <ComboBox
          :model-value="selectedSourceType"
          :options="sourceTypeOptions"
          class="w-40 [&>div>button]:bg-n-alpha-black2"
          @update:model-value="handleSourceTypeChange"
        />
        <Input
          v-model="searchQuery"
          :placeholder="$t('CAPTAIN.SOURCES.SEARCH_PLACEHOLDER')"
          icon="i-lucide-search"
          class="max-w-xs"
          @input="handleSearchInput"
        />
      </div>
    </template>

    <template #body>
      <div class="flex flex-col gap-4">
        <SourceCard
          v-for="source in sources"
          :id="source.id"
          :key="source.id"
          :title="source.title"
          :source-type="source.source_type"
          :external-link="source.external_link"
          :status="source.status"
          :created-at="source.created_at"
          @action="handleAction"
        />
      </div>
    </template>

    <CreateSourceDialog
      v-if="showCreateDialog"
      ref="createSourceDialog"
      @close="handleCreateDialogClose"
    />
    <DeleteDialog
      v-if="selectedSource"
      ref="deleteSourceDialog"
      :entity="selectedSource"
      type="Sources"
      translation-key="SOURCES"
      @delete-success="onDeleteSuccess"
    />
  </PageLayout>
</template>
