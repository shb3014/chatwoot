<script>
import { ref, watch } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import { Ckeditor } from '@ckeditor/ckeditor5-vue';
import DOMPurify from 'dompurify';

// 导入 CKEditor5 样式
import 'ckeditor5/ckeditor5.css';
// 导入 CKEditor5 内容样式（用于编辑区域内的标题、段落等元素）
import 'ckeditor5/ckeditor5-content.css';

// CKEditor5 核心编辑器
import { ClassicEditor as ClassicEditorBase } from 'ckeditor5';

// CKEditor5 插件
import { Essentials } from 'ckeditor5';
import { Bold, Italic } from 'ckeditor5';
import { Link } from 'ckeditor5';
import { Paragraph } from 'ckeditor5';
import { Heading } from 'ckeditor5';
import { List } from 'ckeditor5';
import { BlockQuote } from 'ckeditor5';
import { Table, TableToolbar } from 'ckeditor5';
import { MediaEmbed } from 'ckeditor5';
import { HtmlEmbed } from 'ckeditor5';
import { Undo } from 'ckeditor5';
import {
  Image,
  ImageCaption,
  ImageResize,
  ImageStyle,
  ImageToolbar,
  ImageUpload,
} from 'ckeditor5';

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
      HtmlEmbed,
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
      licenseKey: 'GPL',
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
          'htmlEmbed',
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
      mediaEmbed: {
        previewsInData: true,
        providers: [
          // YouTube (保留默认支持)
          {
            name: 'youtube',
            url: [
              /^https?:\/\/(?:www\.)?(?:youtube\.com\/watch\?v=|youtu\.be\/)([^&\n?#]+)/,
              /^https?:\/\/(?:www\.)?youtube\.com\/embed\/([^&\n?#]+)/,
            ],
            html: match => {
              const videoId = match[1];
              return (
                '<div style="position: relative; padding-bottom: 56.25%; height: 0;">' +
                `<iframe src="https://www.youtube-nocookie.com/embed/${videoId}" ` +
                'style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;" ' +
                'frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture" ' +
                'allowfullscreen></iframe></div>'
              );
            },
          },
          // Vimeo (保留默认支持)
          {
            name: 'vimeo',
            url: [/^https?:\/\/(?:www\.)?vimeo\.com\/(\d+)/],
            html: match => {
              const videoId = match[1];
              return (
                '<div style="position: relative; padding-bottom: 56.25%; height: 0;">' +
                `<iframe src="https://player.vimeo.com/video/${videoId}?dnt=true" ` +
                'style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;" ' +
                'frameborder="0" allow="autoplay; fullscreen; picture-in-picture" ' +
                'allowfullscreen></iframe></div>'
              );
            },
          },
          // CDN 视频文件支持（.mp4, .webm, .ogg 等）
          {
            name: 'video',
            url: [
              /^https?:\/\/.+\.(mp4|webm|ogg|ogv|mov|avi|wmv|flv|mkv)(\?.*)?$/i,
            ],
            html: match => {
              const videoUrl = match[0];
              // 从 URL 中提取文件扩展名以确定 MIME 类型
              const extension = videoUrl.match(/\.([^.?#]+)/)?.[1]?.toLowerCase();
              const mimeTypes = {
                mp4: 'video/mp4',
                webm: 'video/webm',
                ogg: 'video/ogg',
                ogv: 'video/ogg',
                mov: 'video/quicktime',
                avi: 'video/x-msvideo',
                wmv: 'video/x-ms-wmv',
                flv: 'video/x-flv',
                mkv: 'video/x-matroska',
              };
              const mimeType = mimeTypes[extension] || 'video/mp4';

              return (
                '<div style="display: flex;justify-content: center;">' +
                '<video width="320" height="180" playsinline preload="metadata" controls style="max-width: 100%; height: auto;">' +
                `<source src="${videoUrl}#t=0.001" type="${mimeType}">` +
                'Your browser does not support the video tag.' +
                '</video>' +
                '</div>'
              );
            },
          },
        ],
      },
      htmlEmbed: {
        showPreviews: true,
        sanitizeHtml: inputHtml => {
          const sanitizedHtml = DOMPurify.sanitize(inputHtml, {
            ADD_TAGS: ['iframe', 'video', 'audio', 'source'],
            ADD_ATTR: [
              'target',
              'allow',
              'allowfullscreen',
              'frameborder',
              'controls',
              'playsinline',
              'preload',
            ],
          });
          return {
            html: sanitizedHtml,
            hasChanged: sanitizedHtml !== inputHtml,
          };
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

  // 编辑器内容样式
  .ck-editor__editable {
    // 标题样式
    h1 {
      font-size: 2em;
      font-weight: 700;
      line-height: 1.2;
      margin: 0.67em 0;
      color: inherit;
    }

    h2 {
      font-size: 1.5em;
      font-weight: 700;
      line-height: 1.3;
      margin: 0.83em 0;
      color: inherit;
    }

    h3 {
      font-size: 1.25em;
      font-weight: 600;
      line-height: 1.4;
      margin: 1em 0;
      color: inherit;
    }

    // 段落样式
    p {
      margin: 0.5em 0;
      line-height: 1.6;
    }

    // 图片样式
    figure.image {
      margin: 1em auto;

      figcaption {
        padding: 0.5em 0.8em;
        font-size: 0.875em;
        line-height: 1.5;
        min-height: auto !important;
        max-height: 4em;
        overflow: hidden;
        word-wrap: break-word;

        &:empty::before {
          content: attr(data-placeholder);
          color: #999;
        }
      }
    }

    // 图片调整大小手柄样式优化
    .image-resizer {
      display: block;
    }

    // 引用样式
    blockquote {
      border-left: 4px solid #ccc;
      margin: 1em 0;
      padding-left: 1em;
      font-style: italic;
    }

    // 列表样式
    ul, ol {
      margin: 0.5em 0;
      padding-left: 2em;
    }

    // 表格样式
    table {
      border-collapse: collapse;
      margin: 1em 0;

      td, th {
        border: 1px solid #ddd;
        padding: 0.5em;
      }

      th {
        background: #f5f5f5;
        font-weight: 600;
      }
    }

    // HTML 嵌入块样式
    .raw-html-embed {
      margin: 1em 0;
      border-radius: 4px;
      @apply border border-n-weak;

      .raw-html-embed__content-wrapper {
        @apply bg-n-background;
      }
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
