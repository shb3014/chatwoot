<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRouter } from 'vue-router';
import { debounce } from '@chatwoot/utils';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import CaptainPaywall from 'dashboard/components-next/captain/pageComponents/Paywall.vue';

const store = useStore();
const router = useRouter();

const uiFlags = useMapGetter('captainLearnedConversations/getUIFlags');
const learnedConversations = useMapGetter(
  'captainLearnedConversations/getRecords'
);
const meta = useMapGetter('captainLearnedConversations/getMeta');

const isFetching = computed(() => uiFlags.value.fetchingList);
const isEmpty = computed(() => !learnedConversations.value.length);

const searchQuery = ref('');
const isRemoving = ref(false);

const fetchLearnedConversations = (page = 1) => {
  store.dispatch('captainLearnedConversations/get', {
    page,
    search: searchQuery.value,
    status: 'learned',
  });
};

const debouncedSearch = debounce(() => {
  fetchLearnedConversations();
}, 400);

const onPageChange = page => {
  fetchLearnedConversations(page);
};

const openConversation = conversationId => {
  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: conversationId },
  });
};

const removeLearning = async learningId => {
  if (!learningId) return;
  isRemoving.value = true;
  try {
    await store.dispatch('captainLearnedConversations/delete', learningId);
    fetchLearnedConversations(meta.value?.page || 1);
  } finally {
    isRemoving.value = false;
  }
};

const formatLearnedAt = timestamp => {
  if (!timestamp) return '';
  return new Date(timestamp * 1000).toLocaleString();
};

onMounted(() => {
  fetchLearnedConversations();
});
</script>

<template>
  <PageLayout
    :total-count="meta.totalCount || 0"
    :current-page="meta.page || 1"
    :header-title="$t('CAPTAIN.CONVERSATIONS.HEADER')"
    :is-fetching="isFetching"
    :is-empty="isEmpty"
    :show-pagination-footer="!isFetching && !!learnedConversations.length"
    :feature-flag="FEATURE_FLAGS.CAPTAIN"
    @update:current-page="onPageChange"
  >
    <template #controls>
      <div class="mb-4 -mt-3 flex justify-end">
        <Input
          v-model="searchQuery"
          :placeholder="$t('CAPTAIN.CONVERSATIONS.SEARCH_PLACEHOLDER')"
          class="w-64"
          size="sm"
          @input="debouncedSearch"
        />
      </div>
    </template>

    <template #emptyState>
      <div class="py-12 text-center">
        <p class="text-lg font-medium text-n-slate-12">
          {{ $t('CAPTAIN.CONVERSATIONS.EMPTY_STATE.TITLE') }}
        </p>
        <p class="mt-2 text-sm text-n-slate-11">
          {{ $t('CAPTAIN.CONVERSATIONS.EMPTY_STATE.SUBTITLE') }}
        </p>
      </div>
    </template>

    <template #paywall>
      <CaptainPaywall />
    </template>

    <template #body>
      <div class="flex flex-col gap-4">
        <div
          v-for="learning in learnedConversations"
          :key="learning.id"
          class="border border-n-weak rounded-xl p-4 bg-n-solid-2"
        >
          <div class="flex items-start justify-between gap-4">
            <div class="min-w-0">
              <p class="text-xs text-n-slate-11">
                {{
                  $t('CAPTAIN.CONVERSATIONS.LEARNED_AT', {
                    time: formatLearnedAt(learning.learned_at),
                  })
                }}
                <span v-if="learning.quality_rating != null" class="ml-2">
                  {{
                    $t('CAPTAIN.CONVERSATIONS.RATING', {
                      rating: learning.quality_rating,
                    })
                  }}
                </span>
                <span class="ml-2 inline-flex items-center gap-2">
                  <Button
                    size="xs"
                    color="slate"
                    :label="$t('CAPTAIN.CONVERSATIONS.VIEW_CONVERSATION')"
                    :disabled="!learning.conversation?.display_id"
                    @click="openConversation(learning.conversation?.display_id)"
                  />
                  <Button
                    size="xs"
                    color="slate"
                    :label="$t('CAPTAIN.CONVERSATIONS.REMOVE')"
                    :disabled="isRemoving"
                    :is-loading="isRemoving"
                    @click="removeLearning(learning.id)"
                  />
                </span>
              </p>
              <div class="mt-3">
                <p class="text-xs uppercase text-n-slate-10 font-semibold">
                  {{ $t('CAPTAIN.CONVERSATIONS.ISSUE_LABEL') }}
                </p>
                <p class="mt-1 text-sm text-n-slate-12">
                  {{ learning.issue_summary || '-' }}
                </p>
              </div>
              <div class="mt-3">
                <p class="text-xs uppercase text-n-slate-10 font-semibold">
                  {{ $t('CAPTAIN.CONVERSATIONS.RESOLUTION_LABEL') }}
                </p>
                <p class="mt-1 text-sm text-n-slate-12">
                  {{ learning.resolution_summary || '-' }}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </template>
  </PageLayout>
</template>
