<script setup>
import { computed } from 'vue';
import { debounce } from '@chatwoot/utils';
import { useI18n } from 'vue-i18n';

import HelpCenterLayout from 'dashboard/components-next/HelpCenter/HelpCenterLayout.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import CKEditor5 from 'dashboard/components/widgets/CKEditor5/CKEditor5.vue';
import ArticleEditorHeader from 'dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditorHeader.vue';
import ArticleEditorControls from 'dashboard/components-next/HelpCenter/Pages/ArticleEditorPage/ArticleEditorControls.vue';

const props = defineProps({
  article: {
    type: Object,
    default: () => ({}),
  },
  isUpdating: {
    type: Boolean,
    default: false,
  },
  isSaved: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'saveArticle',
  'saveArticleAsync',
  'goBack',
  'setAuthor',
  'setCategory',
  'previewArticle',
]);

const { t } = useI18n();

const isNewArticle = computed(() => !props.article?.id);

const saveAndSync = value => {
  emit('saveArticle', value);
};

// this will only send the data to the backend
// but will not update the local state preventing unnecessary re-renders
// since the data is already saved and we keep the editor text as the source of truth
const quickSave = debounce(
  value => emit('saveArticleAsync', value),
  400,
  false
);

// 2.5 seconds is enough to know that the user has stopped typing and is taking a pause
// so we can save the data to the backend and retrieve the updated data
// this will update the local state with response data
// Only use to save for existing articles
const saveAndSyncDebounced = debounce(saveAndSync, 2500, false);

// Debounced save for new articles
const quickSaveNewArticle = debounce(saveAndSync, 400, false);

const handleSave = value => {
  if (isNewArticle.value) {
    quickSaveNewArticle(value);
  } else {
    quickSave(value);
    saveAndSyncDebounced(value);
  }
};

const articleTitle = computed({
  get: () => props.article.title,
  set: value => {
    handleSave({ title: value });
  },
});

const articleContent = computed({
  get: () => props.article.content,
  set: content => {
    handleSave({ content });
  },
});

const onClickGoBack = () => {
  emit('goBack');
};

const setAuthorId = authorId => {
  emit('setAuthor', authorId);
};

const setCategoryId = categoryId => {
  emit('setCategory', categoryId);
};

const previewArticle = () => {
  emit('previewArticle');
};
</script>

<template>
  <HelpCenterLayout :show-header-title="false" :show-pagination-footer="false">
    <template #header-actions>
      <ArticleEditorHeader
        :is-updating="isUpdating"
        :is-saved="isSaved"
        :status="article.status"
        :article-id="article.id"
        @go-back="onClickGoBack"
        @preview-article="previewArticle"
      />
    </template>
    <template #content>
      <div class="flex flex-col gap-3 pl-4 mb-3 rtl:pr-3 rtl:pl-0">
        <TextArea
          v-model="articleTitle"
          auto-height
          min-height="4rem"
          custom-text-area-class="!text-[32px] !leading-[48px] !font-medium !tracking-[0.2px]"
          custom-text-area-wrapper-class="border-0 !bg-transparent dark:!bg-transparent !py-0 !px-0"
          placeholder="Title"
          autofocus
        />
        <ArticleEditorControls
          :article="article"
          @save-article="saveAndSync"
          @set-author="setAuthorId"
          @set-category="setCategoryId"
        />
      </div>
      <CKEditor5
        v-model="articleContent"
        class="py-0 pb-10 pl-4 rtl:pr-4 rtl:pl-0"
        :placeholder="
          t('HELP_CENTER.EDIT_ARTICLE_PAGE.EDIT_ARTICLE.EDITOR_PLACEHOLDER')
        "
        :autofocus="false"
        min-height="400px"
      />
    </template>
  </HelpCenterLayout>
</template>

<style lang="scss" scoped>
// CKEditor styles are handled in the CKEditor5 component
</style>
