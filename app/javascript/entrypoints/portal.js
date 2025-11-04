import Rails from '@rails/ujs';
import Turbolinks from 'turbolinks';
import '../portal/application.scss';
import { InitializationHelpers } from '../portal/portalHelpers';

// 导入 CKEditor5 内容样式，用于渲染文章内容
import 'ckeditor5/ckeditor5-content.css';

Rails.start();
Turbolinks.start();

document.addEventListener('turbolinks:load', InitializationHelpers.onLoad);
