<script setup>
import { reactive, computed, ref, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { requiredIf, url } from '@vuelidate/validators';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const emit = defineEmits(['submit', 'cancel']);

const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB

const { t } = useI18n();

const formState = {
  uiFlags: useMapGetter('captainSources/getUIFlags'),
};

const initialState = {
  title: '',
  url: '',
  content: '',
  sourceType: 'web_url',
  pdfFile: null,
};

const state = reactive({ ...initialState });
const fileInputRef = ref(null);

const isTitleRequired = computed(() => state.sourceType === 'private_article');

const validationRules = {
  title: {
    required: requiredIf(() => state.sourceType === 'private_article'),
  },
  url: {
    required: requiredIf(() => state.sourceType === 'web_url'),
    url: requiredIf(() => state.sourceType === 'web_url' && url),
  },
  content: {
    required: requiredIf(() => state.sourceType === 'private_article'),
  },
  pdfFile: {
    required: requiredIf(() => state.sourceType === 'pdf'),
  },
};

const sourceTypeOptions = [
  { value: 'web_url', label: t('CAPTAIN.SOURCES.SOURCE_TYPES.WEB_URL') },
  { value: 'pdf', label: t('CAPTAIN.SOURCES.SOURCE_TYPES.PDF') },
  {
    value: 'private_article',
    label: t('CAPTAIN.SOURCES.SOURCE_TYPES.PRIVATE_ARTICLE'),
  },
];

const v$ = useVuelidate(validationRules, state);

const isLoading = computed(() => formState.uiFlags.value.creatingItem);

const getErrorMessage = (field, errorKey) => {
  return v$.value[field].$error
    ? t(`CAPTAIN.SOURCES.FORM.${errorKey}.ERROR`)
    : '';
};

const formErrors = computed(() => ({
  title: getErrorMessage('title', 'TITLE'),
  url: getErrorMessage('url', 'URL'),
  content: getErrorMessage('content', 'CONTENT'),
  pdfFile: getErrorMessage('pdfFile', 'PDF_FILE'),
}));

const handleCancel = () => emit('cancel');

const handleFileChange = event => {
  const file = event.target.files[0];
  if (file) {
    if (file.type !== 'application/pdf') {
      useAlert(t('CAPTAIN.SOURCES.FORM.PDF_FILE.INVALID_TYPE'));
      event.target.value = '';
      return;
    }
    if (file.size > MAX_FILE_SIZE) {
      useAlert(t('CAPTAIN.SOURCES.FORM.PDF_FILE.TOO_LARGE'));
      event.target.value = '';
      return;
    }
    state.pdfFile = file;
    if (!state.title) {
      state.title = file.name.replace(/\.pdf$/i, '');
    }
  }
};

const openFileDialog = () => {
  nextTick(() => {
    if (fileInputRef.value) {
      fileInputRef.value.click();
    }
  });
};

const prepareSourceDetails = () => {
  if (state.sourceType === 'pdf') {
    const formData = new FormData();
    formData.append('source[source_type]', state.sourceType);
    if (state.title) formData.append('source[title]', state.title);
    formData.append('source[pdf_file]', state.pdfFile);
    return formData;
  }

  const payload = {
    source: {
      source_type: state.sourceType,
    },
  };

  if (state.title) payload.source.title = state.title;

  if (state.sourceType === 'web_url') {
    payload.source.external_link = state.url;
  } else if (state.sourceType === 'private_article') {
    payload.source.title = state.title;
    payload.source.content = state.content;
  }

  return payload;
};

const handleSubmit = async () => {
  const isFormValid = await v$.value.$validate();
  if (!isFormValid) {
    return;
  }
  emit('submit', prepareSourceDetails());
};
</script>

<template>
  <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
    <div class="flex flex-col gap-1">
      <label
        for="sourceType"
        class="mb-0.5 text-sm font-medium text-n-slate-12"
      >
        {{ t('CAPTAIN.SOURCES.FORM.TYPE.LABEL') }}
      </label>
      <ComboBox
        id="sourceType"
        v-model="state.sourceType"
        :options="sourceTypeOptions"
        class="[&>div>button]:bg-n-alpha-black2"
      />
    </div>

    <Input
      v-model="state.title"
      :label="
        isTitleRequired
          ? t('CAPTAIN.SOURCES.FORM.TITLE.LABEL')
          : t('CAPTAIN.SOURCES.FORM.TITLE.LABEL_OPTIONAL')
      "
      :placeholder="t('CAPTAIN.SOURCES.FORM.TITLE.PLACEHOLDER')"
      :message="formErrors.title"
      :message-type="formErrors.title ? 'error' : 'info'"
    />

    <Input
      v-if="state.sourceType === 'web_url'"
      v-model="state.url"
      :label="t('CAPTAIN.SOURCES.FORM.URL.LABEL')"
      :placeholder="t('CAPTAIN.SOURCES.FORM.URL.PLACEHOLDER')"
      :message="formErrors.url"
      :message-type="formErrors.url ? 'error' : 'info'"
    />

    <div v-if="state.sourceType === 'pdf'" class="flex flex-col gap-2">
      <label class="text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.SOURCES.FORM.PDF_FILE.LABEL') }}
      </label>
      <div class="relative">
        <input
          ref="fileInputRef"
          type="file"
          accept=".pdf"
          class="hidden"
          @change="handleFileChange"
        />
        <Button
          type="button"
          :color="formErrors.pdfFile ? 'ruby' : 'slate'"
          :variant="formErrors.pdfFile ? 'outline' : 'solid'"
          class="!w-full !h-auto !justify-between !py-4"
          @click="openFileDialog"
        >
          <template #default>
            <div class="flex gap-2 items-center">
              <div
                class="flex justify-center items-center w-10 h-10 rounded-lg bg-n-slate-3"
              >
                <i class="text-xl i-ph-file-pdf text-n-slate-11" />
              </div>
              <div class="flex flex-col flex-1 gap-1 items-start">
                <p class="m-0 text-sm font-medium text-n-slate-12">
                  {{
                    state.pdfFile
                      ? state.pdfFile.name
                      : t('CAPTAIN.SOURCES.FORM.PDF_FILE.CHOOSE_FILE')
                  }}
                </p>
                <p class="m-0 text-xs text-n-slate-11">
                  {{
                    state.pdfFile
                      ? `${(state.pdfFile.size / 1024 / 1024).toFixed(2)} MB`
                      : t('CAPTAIN.SOURCES.FORM.PDF_FILE.HELP_TEXT')
                  }}
                </p>
              </div>
            </div>
            <i class="i-lucide-upload text-n-slate-11" />
          </template>
        </Button>
      </div>
      <p v-if="formErrors.pdfFile" class="text-xs text-n-ruby-9">
        {{ formErrors.pdfFile }}
      </p>
    </div>

    <div
      v-if="state.sourceType === 'private_article'"
      class="flex flex-col gap-1"
    >
      <label class="mb-0.5 text-sm font-medium text-n-slate-12">
        {{ t('CAPTAIN.SOURCES.FORM.CONTENT.LABEL') }}
      </label>
      <TextArea
        v-model="state.content"
        :placeholder="t('CAPTAIN.SOURCES.FORM.CONTENT.PLACEHOLDER')"
        :has-error="!!formErrors.content"
        min-height="8rem"
      />
      <p v-if="formErrors.content" class="text-xs text-n-ruby-9">
        {{ formErrors.content }}
      </p>
    </div>

    <div class="flex gap-3 justify-between items-center w-full">
      <Button
        type="button"
        variant="faded"
        color="slate"
        :label="t('CAPTAIN.FORM.CANCEL')"
        class="w-full bg-n-alpha-2 text-n-blue-text hover:bg-n-alpha-3"
        @click="handleCancel"
      />
      <Button
        type="submit"
        :label="t('CAPTAIN.FORM.CREATE')"
        class="w-full"
        :is-loading="isLoading"
        :disabled="isLoading"
      />
    </div>
  </form>
</template>
