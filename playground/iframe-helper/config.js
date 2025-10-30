// Widget 测试配置文件
// 修改这里的配置后，点击"重新挂载"即可应用

export const widgetConfig = {
  // ========== 基础配置 ==========
  position: 'right',              // 'left' 或 'right'
  widgetStyle: 'standard',        // 'standard' 或 'flat'
  darkMode: 'auto',               // 'auto', 'light', 或 'dark'
  locale: 'en',                   // 语言代码

  // ========== 显示选项 ==========
  hideMessageBubble: false,       // 是否隐藏气泡
  showPopoutButton: false,        // 是否显示弹出按钮
  showUnreadMessagesDialog: true,

  // ========== 功能开关 ==========
  enableFileUpload: true,
  enableEmojiPicker: true,
  enableEndConversation: true,

  // ========== 其他配置 ==========
  baseDomain: '',
  isOpen: false,
  type: 'standard',
  hasLoaded: false,
};

export const channelConfig = {
  // ========== 视觉配置 ==========
  widgetColor: '#009CE0',         // 气泡颜色
  websiteName: 'PlantsIO',
  websiteToken: 'LEEuDASKDTq2i6Tka4nbpVmv',

  // ========== 气泡动画配置 ==========
  // 设置为 null 或空字符串以禁用
  bubbleAnimationsConfig: {
    intro_animation_url: 'https://d2yysiie7eha49.cloudfront.net/intro2.webp',  // 入场动画（加载后 0.5 秒播放）
    open_animation_url: 'https://d2yysiie7eha49.cloudfront.net/open.webp',   // 打开动画（气泡打开时播放）
    close_animation_url: 'https://d2yysiie7eha49.cloudfront.net/close.webp',  // 关闭动画（气泡关闭时播放）
  },

  // ========== 欢迎信息 ==========
  welcomeTitle: '',
  welcomeTagline: '',
  availableMessage: '',
  unavailableMessage: '',

  // ========== 其他渠道配置 ==========
  avatarUrl: 'https://via.placeholder.com/48/009CE0/FFFFFF?text=CW',
  hasAConnectedAgentBot: '',
  replyTime: 'in_a_few_hours',
  disableBranding: true,
};

// ========== 快速配置预设 ==========
export const presets = {
  // 默认配置（带入场动画）
  default: {
    widgetColor: '#009CE0',
    bubbleAnimationsConfig: {
      intro_animation_url: 'https://d2yysiie7eha49.cloudfront.net/cat.gif',
      open_animation_url: '',
      close_animation_url: '',
    },
  },

  // 无动画
  noAnimation: {
    widgetColor: '#009CE0',
    bubbleAnimationsConfig: null,
  },

  // 完整动画（示例 - 需要替换为真实的动画 URL）
  fullAnimation: {
    widgetColor: '#2563eb',
    bubbleAnimationsConfig: {
      intro_animation_url: 'https://d2yysiie7eha49.cloudfront.net/cat.gif',
      open_animation_url: 'https://example.com/open.gif',
      close_animation_url: 'https://example.com/close.gif',
    },
  },

  // 深色主题
  darkTheme: {
    widgetColor: '#1f2937',
    bubbleAnimationsConfig: null,
  },
};

