<script>
import { ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import { Ckeditor } from '@ckeditor/ckeditor5-vue';

// CKEditor5 核心编辑器
import { ClassicEditor as ClassicEditorBase } from '@ckeditor/ckeditor5-editor-classic';

// CKEditor5 插件
import { Essentials } from '@ckeditor/ckeditor5-essentials';
import { Bold, Italic } from '@ckeditor/ckeditor5-basic-styles';
import { Link } from '@ckeditor/ckeditor5-link';
import { Paragraph } from '@ckeditor/ckeditor5-paragraph';
import { Heading } from '@ckeditor/ckeditor5-heading';
import { List } from '@ckeditor/ckeditor5-list';
import { BlockQuote } from '@ckeditor/ckeditor5-block-quote';
import { Table, TableToolbar } from '@ckeditor/ckeditor5-table';
import { MediaEmbed } from '@ckeditor/ckeditor5-media-embed';
import { Undo } from '@ckeditor/ckeditor5-undo';
import {
  Image,
  ImageCaption,
  ImageResize,
  ImageStyle,
  ImageToolbar,
  ImageUpload,
} from '@ckeditor/ckeditor5-image';

export default {
  name: 'CKEditor5',
  components: {
    ckeditor: Ckeditor,
  },
  props: {
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
  },
  emits: ['update:modelValue', 'blur', 'focus'],
  setup(props, { emit }) {
    const { t } = useI18n();
    const route = useRoute();
    const store = useStore();

    const editorData = ref(props.modelValue || '');

    // 创建自定义编辑器类
    class CustomEditor extends ClassicEditorBase {}

    // 配置内置插件
    CustomEditor.builtinPlugins = [
      Essentials,
      Bold,
      Italic,
      Link,
      Paragraph,
      Heading,
      List,
      BlockQuote,
      Table,
      TableToolbar,
      MediaEmbed,
      Undo,
      Image,
      ImageCaption,
      ImageResize,
      ImageStyle,
      ImageToolbar,
      ImageUpload,
    ];

    const editor = CustomEditor;
    const editorInstance = ref(null);

    const MAXIMUM_FILE_UPLOAD_SIZE = 4; // MB

    // 自定义图片上传适配器
    class UploadAdapter {
      constructor(loader) {
        this.loader = loader;
      }

      upload() {
        return this.loader.file.then(async file => {
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
        });
      }

      abort() {
        // 取消上传的逻辑（可选）
      }
    }

    // 编辑器配置
    const editorConfig = {
      placeholder: props.placeholder,
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
          '|',
          'resizeImage',
        ],
        resizeOptions: [
          {
            name: 'resizeImage:original',
            label: 'Original',
            value: null,
          },
          {
            name: 'resizeImage:25',
            label: '25%',
            value: '25',
          },
          {
            name: 'resizeImage:50',
            label: '50%',
            value: '50',
          },
          {
            name: 'resizeImage:75',
            label: '75%',
            value: '75',
          },
        ],
        resizeUnit: '%',
      },
      table: {
        contentToolbar: ['tableColumn', 'tableRow', 'mergeTableCells'],
      },
      heading: {
        options: [
          {
            model: 'paragraph',
            title: 'Paragraph',
            class: 'ck-heading_paragraph',
          },
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
        if (editorData.value !== newValue) {
          editorData.value = newValue;
        }
      }
    );

    // 编辑器准备好时的回调
    const onEditorReady = instance => {
      editorInstance.value = instance;

      // 注册自定义图片上传适配器
      instance.plugins.get('FileRepository').createUploadAdapter = loader => {
        return new UploadAdapter(loader);
      };

      if (props.autofocus) {
        instance.editing.view.focus();
      }
    };

    // 编辑器内容变化时的回调
    const onEditorInput = data => {
      editorData.value = data;
      emit('update:modelValue', data);
    };

    // 编辑器获得焦点
    const onEditorFocus = () => {
      emit('focus');
    };

    // 编辑器失去焦点
    const onEditorBlur = () => {
      emit('blur');
    };

    return {
      editorData,
      editor,
      editorConfig,
      editorInstance,
      onEditorReady,
      onEditorInput,
      onEditorFocus,
      onEditorBlur,
    };
  },
};
</script>

<template>
  <div class="ckeditor5-wrapper" :style="{ '--min-height': minHeight }">
    <ckeditor
      v-model="editorData"
      :editor="editor"
      :config="editorConfig"
      @ready="onEditorReady"
      @input="onEditorInput"
      @focus="onEditorFocus"
      @blur="onEditorBlur"
    />
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
