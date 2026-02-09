<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { frontendURL } from 'dashboard/helper/URLHelper';

import PageLayout from 'dashboard/components-next/captain/PageLayout.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const route = useRoute();
const router = useRouter();
const store = useStore();
const { t } = useI18n();
const { accountId } = useAccount();

const uiFlags = useMapGetter('captainSources/getUIFlags');
const sourceRecord = useMapGetter('captainSources/getRecord');

const sourceId = computed(() => route.params.sourceId);
const source = computed(() => sourceRecord.value(sourceId.value));
const isLoading = computed(() => uiFlags.value.fetchingItem);
const isUpdating = computed(() => uiFlags.value.updatingItem);

const editTitle = ref('');
const editContent = ref('');

const backUrl = computed(() =>
  frontendURL(`accounts/${accountId.value}/captain/sources`)
);

const isPrivateArticle = computed(
  () => source.value?.source_type === 'private_article'
);

const fetchSource = async () => {
  try {
    await store.dispatch('captainSources/show', sourceId.value);
    editTitle.value = source.value?.title || '';
    editContent.value = source.value?.content || '';
  } catch (error) {
    useAlert(t('CAPTAIN.SOURCES.UPDATE.ERROR_MESSAGE'));
  }
};

const handleSave = async () => {
  try {
    await store.dispatch('captainSources/update', {
      id: sourceId.value,
      source: {
        title: editTitle.value,
        content: editContent.value,
      },
    });
    useAlert(t('CAPTAIN.SOURCES.UPDATE.SUCCESS_MESSAGE'));
    router.push(backUrl.value);
  } catch (error) {
    useAlert(t('CAPTAIN.SOURCES.UPDATE.ERROR_MESSAGE'));
  }
};

const handleBack = () => {
  router.push(backUrl.value);
};

onMounted(() => {
  fetchSource();
});
</script>

<template>
  <PageLayout
    :header-title="source?.title || t('CAPTAIN.SOURCES.HEADER')"
    :back-url="backUrl"
    :show-pagination-footer="false"
    :is-fetching="isLoading"
    :is-empty="false"
  >
    <template #body>
      <div v-if="isLoading" class="flex items-center justify-center py-10">
        <Spinner />
      </div>
      <div v-else class="flex flex-col gap-6 max-w-3xl">
        <!-- Source metadata -->
        <div class="flex gap-4 items-center text-sm text-n-slate-11">
          <span class="flex gap-1 items-center">
            <i
              :class="{
                'i-ph-globe-duotone': source?.source_type === 'web_url',
                'i-ph-file-pdf-duotone': source?.source_type === 'pdf',
                'i-ph-article-duotone':
                  source?.source_type === 'private_article',
              }"
            />
            {{
              source?.source_type === 'web_url'
                ? t('CAPTAIN.SOURCES.SOURCE_TYPES.WEB_URL')
                : source?.source_type === 'pdf'
                  ? t('CAPTAIN.SOURCES.SOURCE_TYPES.PDF')
                  : t('CAPTAIN.SOURCES.SOURCE_TYPES.PRIVATE_ARTICLE')
            }}
          </span>
          <span
            :class="{
              'text-n-green-11': source?.status === 'active',
              'text-n-amber-11': source?.status === 'pending',
              'text-n-blue-11': source?.status === 'processing',
              'text-n-ruby-11': source?.status === 'failed',
            }"
          >
            {{ source?.status }}
          </span>
        </div>

        <!-- URL display for web_url sources -->
        <div
          v-if="source?.source_type === 'web_url' && source?.external_link"
          class="flex items-center gap-2 p-3 rounded-lg bg-n-slate-3"
        >
          <i class="i-ph-link-simple text-n-slate-11" />
          <a
            :href="source.external_link"
            target="_blank"
            rel="noopener noreferrer"
            class="text-sm text-n-blue-11 hover:underline truncate"
          >
            {{ source.external_link }}
          </a>
        </div>

        <!-- Editable title -->
        <Input
          v-model="editTitle"
          :label="t('CAPTAIN.SOURCES.FORM.TITLE.LABEL')"
          :placeholder="t('CAPTAIN.SOURCES.FORM.TITLE.PLACEHOLDER')"
        />

        <!-- Content editor for private articles -->
        <div v-if="isPrivateArticle" class="flex flex-col gap-1">
          <label class="mb-0.5 text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN.SOURCES.FORM.CONTENT.LABEL') }}
          </label>
          <TextArea
            v-model="editContent"
            :placeholder="t('CAPTAIN.SOURCES.FORM.CONTENT.PLACEHOLDER')"
            min-height="16rem"
          />
        </div>

        <!-- Content preview for URL/PDF sources (read-only) -->
        <div v-else-if="source?.content" class="flex flex-col gap-1">
          <label class="mb-0.5 text-sm font-medium text-n-slate-12">
            {{ t('CAPTAIN.SOURCES.FORM.CONTENT.CRAWLED_CONTENT_LABEL') }}
          </label>
          <div
            class="p-4 rounded-lg bg-n-slate-3 text-sm text-n-slate-12 max-h-96 overflow-y-auto whitespace-pre-wrap"
          >
            {{ source.content }}
          </div>
        </div>

        <!-- Error info for failed sources -->
        <div
          v-if="source?.status === 'failed' && source?.metadata?.error"
          class="p-3 rounded-lg bg-n-ruby-3 text-sm text-n-ruby-11"
        >
          <strong>{{ t('CAPTAIN.SOURCES.UPDATE.ERROR_LABEL') }}</strong>
          {{ source.metadata.error }}
        </div>

        <!-- Action buttons -->
        <div class="flex gap-3 items-center">
          <Button
            :label="t('CAPTAIN.FORM.CANCEL')"
            variant="faded"
            color="slate"
            @click="handleBack"
          />
          <Button
            v-if="isPrivateArticle"
            :label="t('CAPTAIN.FORM.EDIT')"
            :is-loading="isUpdating"
            :disabled="isUpdating"
            @click="handleSave"
          />
        </div>
      </div>
    </template>
  </PageLayout>
</template>
