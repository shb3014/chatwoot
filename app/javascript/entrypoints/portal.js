import Rails from '@rails/ujs';
import Turbolinks from 'turbolinks';
import '../portal/application.scss';
import { InitializationHelpers } from '../portal/portalHelpers';

// 导入 CKEditor5 内容样式，用于渲染文章内容
import 'ckeditor5/ckeditor5-content.css';

// 导入 oembed 转换器
import { oembedTransformer } from '../portal/oembed-transformer';

Rails.start();
Turbolinks.start();

// Chatwoot widget preservation for Turbolinks navigation
// Store widget elements before Turbolinks replaces the body
let chatwootWidgetCache = {
  bubbleHolder: null,
  widgetHolder: null,
  widgetStyles: null,
};

const cacheWidgetElements = () => {
  const bubble = document.getElementById('cw-bubble-holder');
  const widget = document.getElementById('cw-widget-holder');
  const styles = document.getElementById('cw-widget-styles');

  if (bubble) chatwootWidgetCache.bubbleHolder = bubble;
  if (widget) chatwootWidgetCache.widgetHolder = widget;
  if (styles) chatwootWidgetCache.widgetStyles = styles;
};

const restoreWidgetElements = () => {
  const { bubbleHolder, widgetHolder, widgetStyles } = chatwootWidgetCache;

  if (bubbleHolder && !document.body.contains(bubbleHolder)) {
    document.body.appendChild(bubbleHolder);
  }
  if (widgetHolder && !document.body.contains(widgetHolder)) {
    document.body.appendChild(widgetHolder);
  }
  if (widgetStyles && !document.body.contains(widgetStyles)) {
    document.body.appendChild(widgetStyles);
  }
};

// Cache elements before Turbolinks replaces the body
document.addEventListener('turbolinks:before-render', () => {
  cacheWidgetElements();
});

// Also cache before page is saved to Turbolinks cache
document.addEventListener('turbolinks:before-cache', () => {
  cacheWidgetElements();
});

document.addEventListener('turbolinks:load', () => {
  InitializationHelpers.onLoad();

  // 转换页面中的 oembed 标签
  oembedTransformer.init();

  // Restore Chatwoot widget elements after Turbolinks navigation
  restoreWidgetElements();
});
