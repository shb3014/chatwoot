<script setup>
import { ref, watch, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import ClassicEditor from '@ckeditor/ckeditor5-build-classic';

const props = defineProps({
  modelValue: {
    type: String,
    default: '',
  },
  placeholder: {
    type: String,
    default: '',
  },
  autofocus: {
    type: Boolean,
    default: true,
  },
  minHeight: {
    type: String,
    default: '300px',
  },
});

const emit = defineEmits(['update:modelValue', 'blur', 'focus']);

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const editorRef = ref(null);
const editorInstance = ref(null);

const MAXIMUM_FILE_UPLOAD_SIZE = 4; // MB

// 自定义图片上传适配器
class UploadAdapter {
  constructor(loader, uploadFunction) {
    this.loader = loader;
    this.uploadFunction = uploadFunction;
  }

  upload() {
    return this.loader.file.then(file => this.uploadFunction(file));
  }

  abort() {
    // 取消上传的逻辑（可选）
  }
}

function uploadAdapterPlugin(editor, uploadFunction) {
  editor.plugins.get('FileRepository').createUploadAdapter = loader => {
    return new UploadAdapter(loader, uploadFunction);
  };
}

// 处理图片上传
const handleImageUpload = async file => {
  // 检查文件大小
  if (!checkFileSizeLimit(file, MAXIMUM_FILE_UPLOAD_SIZE)) {
    useAlert(
      t('HELP_CENTER.ARTICLE_EDITOR.IMAGE_UPLOAD.ERROR_FILE_SIZE', {
        size: MAXIMUM_FILE_UPLOAD_SIZE,
      })
    );
    throw new Error('File size exceeds limit');
  }

  try {
    const fileUrl = await store.dispatch('articles/attachImage', {
      portalSlug: route.params.portalSlug,
      file,
    });

    return {
      default: fileUrl,
    };
  } catch (error) {
    useAlert(t('HELP_CENTER.ARTICLE_EDITOR.IMAGE_UPLOAD.ERROR'));
    throw error;
  }
};

// 编辑器配置
const editorConfig = {
  // 使用 GPL 许可证（Chatwoot 是开源项目）
  licenseKey: 'GPL',
  placeholder: props.placeholder,
  extraPlugins: [editor => uploadAdapterPlugin(editor, handleImageUpload)],
  toolbar: {
    items: [
      'heading',
      '|',
      'bold',
      'italic',
      'link',
      '|',
      'bulletedList',
      'numberedList',
      '|',
      'blockQuote',
      'insertTable',
      '|',
      'imageUpload',
      'mediaEmbed',
      '|',
      'undo',
      'redo',
    ],
  },
  image: {
    toolbar: [
      'imageTextAlternative',
      'toggleImageCaption',
      'imageStyle:inline',
      'imageStyle:block',
      'imageStyle:side',
    ],
  },
  table: {
    contentToolbar: ['tableColumn', 'tableRow', 'mergeTableCells'],
  },
  heading: {
    options: [
      { model: 'paragraph', title: 'Paragraph', class: 'ck-heading_paragraph' },
      {
        model: 'heading1',
        view: 'h1',
        title: 'Heading 1',
        class: 'ck-heading_heading1',
      },
      {
        model: 'heading2',
        view: 'h2',
        title: 'Heading 2',
        class: 'ck-heading_heading2',
      },
      {
        model: 'heading3',
        view: 'h3',
        title: 'Heading 3',
        class: 'ck-heading_heading3',
      },
    ],
  },
  link: {
    decorators: {
      openInNewTab: {
        mode: 'manual',
        label: 'Open in a new tab',
        attributes: {
          target: '_blank',
          rel: 'noopener noreferrer',
        },
      },
    },
  },
};

// 监听 modelValue 变化
watch(
  () => props.modelValue,
  newValue => {
    if (editorInstance.value && editorInstance.value.getData() !== newValue) {
      editorInstance.value.setData(newValue || '');
    }
  }
);

// 组件挂载后初始化编辑器
onMounted(async () => {
  try {
    editorInstance.value = await ClassicEditor.create(
      editorRef.value,
      editorConfig
    );

    // 设置初始内容
    if (props.modelValue) {
      editorInstance.value.setData(props.modelValue);
    }

    // 监听内容变化
    editorInstance.value.model.document.on('change:data', () => {
      const data = editorInstance.value.getData();
      emit('update:modelValue', data);
    });

    // 监听焦点和失焦事件
    editorInstance.value.editing.view.document.on('focus', () => {
      emit('focus');
    });

    editorInstance.value.editing.view.document.on('blur', () => {
      emit('blur');
    });

    // 自动聚焦
    if (props.autofocus) {
      editorInstance.value.editing.view.focus();
    }
  } catch (error) {
    console.error('Error initializing CKEditor:', error);
    useAlert('Failed to initialize editor');
  }
});

// 组件卸载时销毁编辑器
const destroyEditor = () => {
  if (editorInstance.value) {
    editorInstance.value.destroy().catch(error => {
      console.error('Error destroying CKEditor:', error);
    });
  }
};

// 使用 beforeUnmount 生命周期钩子
import { onBeforeUnmount } from 'vue';
onBeforeUnmount(() => {
  destroyEditor();
});

// 暴露编辑器实例供父组件使用
defineExpose({
  editorInstance,
});
</script>

<template>
  <div class="ckeditor5-wrapper" :style="{ '--min-height': minHeight }">
    <div ref="editorRef" />
  </div>
</template>

<style lang="scss">
.ckeditor5-wrapper {
  width: 100%;

  .ck-editor__editable {
    min-height: var(--min-height, 300px);
    max-height: 600px;
    overflow-y: auto;
  }

  .ck.ck-editor {
    @apply border-n-weak;
  }

  .ck.ck-toolbar {
    @apply bg-n-solid-2 border-n-weak;
  }

  .ck.ck-editor__editable {
    @apply bg-n-background text-n-slate-12;
  }

  .ck.ck-editor__editable:focus {
    @apply border-n-brand shadow-none;
  }

  .ck.ck-button {
    @apply text-n-slate-11;

    &:hover {
      @apply bg-n-slate-3;
    }

    &.ck-on {
      @apply bg-n-slate-4 text-n-slate-12;
    }
  }

  .ck.ck-dropdown__panel {
    @apply bg-n-solid-2 border-n-weak;
  }

  .ck.ck-list__item {
    @apply text-n-slate-12;

    &:hover {
      @apply bg-n-slate-3;
    }
  }

  // 暗色模式支持
  :global(.dark) & {
    .ck.ck-editor__editable {
      @apply bg-n-solid-1;
    }
  }
}
</style>
