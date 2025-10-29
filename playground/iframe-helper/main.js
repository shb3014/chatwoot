import { IFrameHelper } from '/app/javascript/sdk/IFrameHelper.js';
import { widgetConfig, channelConfig, presets } from './config.js';

// 日志函数，支持不同类型的日志级别
const log = (message, type = 'info', data = null) => {
  const timestamp = new Date().toLocaleTimeString();
  console.log(`[playground ${timestamp}]`, message, data || '');

  const el = document.getElementById('log');
  const line = document.createElement('div');
  line.className = `log-item ${type}`;

  let text = `[${timestamp}] ${message}`;
  if (data) {
    text += '\n  ' + JSON.stringify(data, null, 2).split('\n').join('\n  ');
  }

  line.textContent = text;
  el.appendChild(line);
  el.scrollTop = el.scrollHeight;
};

// 更新状态徽章
const updateStatus = (text, isSuccess = false) => {
  const badge = document.getElementById('widgetStatus');
  badge.textContent = text;
  badge.className = isSuccess ? 'status-badge success' : 'status-badge';
};

// 初始化 window.$chatwoot 配置（从配置文件读取）
window.$chatwoot = { ...widgetConfig };

// 更新配置显示
const updateConfigDisplay = () => {
  document.getElementById('displayColor').textContent = channelConfig.widgetColor;
  document.getElementById('displayPosition').textContent = widgetConfig.position;

  const animConfig = channelConfig.bubbleAnimationsConfig;
  if (animConfig) {
    document.getElementById('displayIntroAnim').textContent =
      animConfig.intro_animation_url || '未设置';
    document.getElementById('displayOpenAnim').textContent =
      animConfig.open_animation_url || '未设置';
    document.getElementById('displayCloseAnim').textContent =
      animConfig.close_animation_url || '未设置';
  } else {
    document.getElementById('displayIntroAnim').textContent = '未设置';
    document.getElementById('displayOpenAnim').textContent = '未设置';
    document.getElementById('displayCloseAnim').textContent = '未设置';
  }
};

// 监听来自 iframe 的消息（原样输出日志）
window.addEventListener('message', e => {
  try {
    if (typeof e.data !== 'string' || !e.data.startsWith('chatwoot-widget:')) return;
    const msg = JSON.parse(e.data.replace('chatwoot-widget:', ''));
    log(`← iframe 事件: ${msg.event}`, 'success', msg);

    // 根据事件类型更新状态
    if (msg.event === 'loaded') {
      updateStatus('✅ 已加载', true);
    }
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

  updateStatus('未挂载', false);
  log('✅ 已清理旧 widget', 'warning');
};

// 挂载 widget
const mountWidget = () => {
  // 重新加载配置（从配置文件）
  Object.assign(window.$chatwoot, widgetConfig);

  // 构建 URL 参数
  const params = new URLSearchParams({
    website_token: channelConfig.websiteToken,
    color: channelConfig.widgetColor
  });

  // 添加动画配置到 URL 参数
  const animConfig = channelConfig.bubbleAnimationsConfig;
  if (animConfig) {
    if (animConfig.intro_animation_url) {
      params.set('intro_animation', animConfig.intro_animation_url);
    }
    if (animConfig.open_animation_url) {
      params.set('open_animation', animConfig.open_animation_url);
    }
    if (animConfig.close_animation_url) {
      params.set('close_animation', animConfig.close_animation_url);
    }
  }

  const widgetUrl = `/widget/index.html?${params.toString()}`;
  console.log('[playground] Widget URL:', widgetUrl);
  console.log('[playground] 配置文件中的配置:', {
    widgetConfig,
    channelConfig,
    bubbleAnimationsConfig: animConfig
  });

  // 在 playground 环境中，直接覆盖 getUrl 方法指向本地 stub
  const originalGetUrl = IFrameHelper.getUrl;
  IFrameHelper.getUrl = ({ websiteToken }) => widgetUrl;

  IFrameHelper.createFrame({ baseUrl: '', websiteToken: channelConfig.websiteToken });
  updateStatus('挂载中...', false);
  log('→ 调用 IFrameHelper.createFrame', 'info', {
    websiteToken: channelConfig.websiteToken,
    widgetUrl: widgetUrl,
    config: window.$chatwoot,
    channelConfig: channelConfig
  });

  // 恢复原方法
  IFrameHelper.getUrl = originalGetUrl;
};

// 绑定按钮
document.getElementById('mount').addEventListener('click', mountWidget);

document.getElementById('remount').addEventListener('click', () => {
  const wasOpen = window.$chatwoot.isOpen;
  unmountWidget();
  // 延迟 100ms 重新挂载，确保 DOM 清理完毕 & Vite HMR 已更新模块
  setTimeout(() => {
    // 重新加载配置文件（Vite HMR 会自动更新）
    import('./config.js?t=' + Date.now()).then(module => {
      // 更新配置显示
      Object.assign(widgetConfig, module.widgetConfig);
      Object.assign(channelConfig, module.channelConfig);
      updateConfigDisplay();

      log('📄 配置已重新加载', 'success', {
        widgetConfig: module.widgetConfig,
        channelConfig: module.channelConfig
      });
    }).then(() => {
      // 强制重新导入 IFrameHelper
      return import('/app/javascript/sdk/IFrameHelper.js?t=' + Date.now());
    }).then(() => {
      mountWidget();
      log('🔄 热重载完成', 'success');
      // 如果之前是打开状态，提示用户可以手动打开
      if (wasOpen) {
        log('💡 之前气泡是打开的，可以点击"打开气泡"按钮重新打开', 'info');
      }
    });
  }, 100);
});

document.getElementById('open').addEventListener('click', () => {
  IFrameHelper.events.toggleBubble('open');
  log('→ 发送 toggleBubble("open")', 'info');
});

document.getElementById('close').addEventListener('click', () => {
  IFrameHelper.events.toggleBubble('close');
  log('→ 发送 toggleBubble("close")', 'info');
});

document.getElementById('unread').addEventListener('click', () => {
  IFrameHelper.events.setUnreadMode();
  log('→ 发送 setUnreadMode()', 'warning');
});

document.getElementById('resetUnread').addEventListener('click', () => {
  IFrameHelper.events.resetUnreadMode();
  log('→ 发送 resetUnreadMode()', 'info');
});

document.getElementById('playAudio').addEventListener('click', () => {
  IFrameHelper.events.playAudio();
  log('→ 发送 playAudio()', 'info');
});

document.getElementById('closeChat').addEventListener('click', () => {
  IFrameHelper.events.closeChat();
  log('→ 发送 closeChat()', 'info');
});

// ============ 模拟 Widget 事件 ============

// 设置气泡文本
document.getElementById('setBubbleLabel').addEventListener('click', () => {
  const labels = ['👋 有新消息', '💬 在线客服', '❓ 需要帮助？', '🎉 欢迎咨询'];
  const label = labels[Math.floor(Math.random() * labels.length)];
  IFrameHelper.sendMessage('setBubbleLabel', { label });
  log('→ 模拟设置气泡文本', 'info', { label });
});

// 发送 Postback
document.getElementById('sendPostback').addEventListener('click', () => {
  const postbackData = {
    id: 'demo-action-' + Date.now(),
    value: Math.floor(Math.random() * 100),
    title: '用户点击了操作按钮'
  };
  IFrameHelper.sendMessage('postback', { data: postbackData });
  log('→ 模拟发送 Postback', 'info', postbackData);
});

// 更新高度
document.getElementById('updateHeight').addEventListener('click', () => {
  const heights = [400, 500, 600];
  const height = heights[Math.floor(Math.random() * heights.length)];
  IFrameHelper.setFrameHeightToFitContent(height, true);
  log('→ 更新 iframe 高度', 'info', { height });
});

// 显示未读通知
document.getElementById('showNotification').addEventListener('click', () => {
  const unreadCount = 3;
  IFrameHelper.events.handleNotificationDot({ unreadMessageCount: unreadCount });
  IFrameHelper.events.setUnreadMode();
  log('→ 显示未读通知', 'warning', { unreadCount });
});

// 清除未读
document.getElementById('clearNotification').addEventListener('click', () => {
  IFrameHelper.events.handleNotificationDot({ unreadMessageCount: 0 });
  IFrameHelper.events.resetUnreadMode();
  log('→ 清除未读通知', 'info');
});

// ============ 模拟消息 ============

// 发送客服消息
document.getElementById('sendAgentMessage').addEventListener('click', () => {
  const input = document.getElementById('customMessageText');
  const text = input.value.trim() || '您好！有什么可以帮助您的吗？';

  IFrameHelper.sendMessage('simulateAgentMessage', {
    sender: '客服 Alice',
    text: text
  });

  log('→ 发送客服消息到 widget', 'success', { text });
  if (input.value.trim()) input.value = '';
});

// 发送用户消息
document.getElementById('sendUserMessage').addEventListener('click', () => {
  const input = document.getElementById('customMessageText');
  const text = input.value.trim() || '你好，我有一个问题。';

  IFrameHelper.sendMessage('simulateUserMessage', {
    text: text
  });

  log('→ 发送用户消息到 widget', 'info', { text });
  if (input.value.trim()) input.value = '';
});

// 清空消息
document.getElementById('clearMessages').addEventListener('click', () => {
  IFrameHelper.sendMessage('clearMessages', {});
  log('→ 清空 widget 消息', 'warning');
});

// 支持回车发送
document.getElementById('customMessageText').addEventListener('keypress', (e) => {
  if (e.key === 'Enter') {
    document.getElementById('sendAgentMessage').click();
  }
});


// 清空日志按钮
document.getElementById('clearLog').addEventListener('click', () => {
  const logEl = document.getElementById('log');
  logEl.innerHTML = '';
  log('📋 日志已清空', 'info');
});

// 页面加载时自动挂载（不自动打开气泡）
window.addEventListener('load', () => {
  // 更新配置显示
  updateConfigDisplay();

  log('🚀 页面加载完成，准备自动挂载 widget', 'info');
  log('📄 配置文件:', 'info', {
    widgetConfig,
    channelConfig
  });

  mountWidget();
  log('💡 Widget 已挂载，点击"打开气泡"按钮或点击页面上的气泡来打开', 'info');
});


