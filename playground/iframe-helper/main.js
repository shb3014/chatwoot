import { IFrameHelper } from '/app/javascript/sdk/IFrameHelper.js';

const log = (...args) => {
  console.log('[playground]', ...args);
  const el = document.getElementById('log');
  const line = document.createElement('div');
  line.textContent = args.map(a => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ');
  el.appendChild(line);
  el.scrollTop = el.scrollHeight;
};

// 最小 window.$chatwoot 配置
window.$chatwoot = {
  position: 'right',
  hideMessageBubble: false,
  widgetStyle: 'standard', // 或 'flat'
  darkMode: false,
  showUnreadMessagesDialog: true,
  showPopoutButton: false,
  isOpen: false,
  type: 'standard', // 或 'expanded'
  locale: 'en',
  baseDomain: '',
  enableFileUpload: false,
  enableEmojiPicker: false,
  enableEndConversation: false,
  hasLoaded: false,
};

// 监听来自 iframe 的消息（原样输出日志）
window.addEventListener('message', e => {
  try {
    if (typeof e.data !== 'string' || !e.data.startsWith('chatwoot-widget:')) return;
    const msg = JSON.parse(e.data.replace('chatwoot-widget:', ''));
    log('← 来自 iframe', msg);
  } catch (_) {}
});

// 清理旧挂载的 widget DOM 与状态
const unmountWidget = () => {
  // 移除 iframe 容器
  const holder = document.getElementById('cw-widget-holder');
  if (holder) holder.remove();
  
  // 移除气泡容器
  const bubble = document.getElementById('cw-bubble-holder');
  if (bubble) bubble.remove();
  
  // 移除样式
  const styles = document.getElementById('cw-widget-styles');
  if (styles) styles.remove();
  
  // 重置全局状态
  window.$chatwoot.isOpen = false;
  window.$chatwoot.hasLoaded = false;
  
  log('✅ 已清理旧 widget');
};

// 挂载 widget
const mountWidget = () => {
  // 在 playground 环境中，直接覆盖 getUrl 方法指向本地 stub
  const originalGetUrl = IFrameHelper.getUrl;
  IFrameHelper.getUrl = ({ websiteToken }) => `/widget/index.html?website_token=${websiteToken}`;
  
  IFrameHelper.createFrame({ baseUrl: '', websiteToken: 'debug-token' });
  log('→ 调用 IFrameHelper.createFrame');
  
  // 恢复原方法（可选，避免影响后续调用）
  IFrameHelper.getUrl = originalGetUrl;
};

// 绑定按钮
document.getElementById('mount').addEventListener('click', mountWidget);

document.getElementById('remount').addEventListener('click', () => {
  const wasOpen = window.$chatwoot.isOpen;
  unmountWidget();
  // 延迟 100ms 重新挂载，确保 DOM 清理完毕 & Vite HMR 已更新模块
  setTimeout(() => {
    // 强制重新导入（Vite HMR 会自动更新，但显式 import 确保拿到最新版本）
    import('/app/javascript/sdk/IFrameHelper.js?t=' + Date.now()).then(() => {
      mountWidget();
      log('🔄 热重载完成');
      // 如果之前是打开状态，重新打开
      if (wasOpen) {
        setTimeout(() => {
          IFrameHelper.events.toggleBubble('open');
          log('→ 自动重新打开气泡');
        }, 300);
      }
    });
  }, 100);
});

document.getElementById('open').addEventListener('click', () => {
  IFrameHelper.events.toggleBubble('open');
  log('→ toggleBubble("open")');
});

document.getElementById('close').addEventListener('click', () => {
  IFrameHelper.events.toggleBubble('close');
  log('→ toggleBubble("close")');
});

document.getElementById('unread').addEventListener('click', () => {
  IFrameHelper.events.setUnreadMode();
  log('→ setUnreadMode()');
});

document.getElementById('resetUnread').addEventListener('click', () => {
  IFrameHelper.events.resetUnreadMode();
  log('→ resetUnreadMode()');
});

document.getElementById('playAudio').addEventListener('click', () => {
  IFrameHelper.events.playAudio();
  log('→ playAudio()');
});

document.getElementById('closeChat').addEventListener('click', () => {
  IFrameHelper.events.closeChat();
  log('→ closeChat()');
});

// 页面加载时自动挂载并打开
window.addEventListener('load', () => {
  mountWidget();
  log('🚀 自动挂载 widget');
  // 等待 iframe loaded 事件后再打开
  setTimeout(() => {
    IFrameHelper.events.toggleBubble('open');
    log('→ 自动打开气泡');
  }, 500);
});


