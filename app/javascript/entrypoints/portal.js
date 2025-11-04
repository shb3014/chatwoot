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

document.addEventListener('turbolinks:load', () => {
  InitializationHelpers.onLoad();

  // 转换页面中的 oembed 标签
  oembedTransformer.init();
});
