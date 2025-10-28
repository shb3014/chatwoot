# IFrameHelper Playground

这是一个用于测试和调试 Chatwoot Widget IFrameHelper 的测试环境。

## 🚀 快速开始

### 启动测试环境

```bash
# 在项目根目录运行
node script/playground-iframe.mjs
# 或
pnpm playground:iframe
```

这将启动一个 Vite 开发服务器，并自动在浏览器中打开测试页面。

### 访问地址

服务器启动后，打开：`http://localhost:5173/playground/iframe-helper/`

## ⚙️ 配置说明

所有配置都在 **`config.js`** 文件中集中管理。

### 修改配置

1. **编辑 `playground/iframe-helper/config.js`**
2. **修改你需要的配置项**
3. **保存文件**
4. **点击页面上的"重新挂载"按钮**

### 主要配置项

#### `widgetConfig` - Widget 基础配置
```javascript
{
  position: 'right',              // 气泡位置: 'left' 或 'right'
  widgetStyle: 'standard',        // 样式: 'standard' 或 'flat'
  darkMode: 'auto',               // 主题: 'auto', 'light', 或 'dark'
  locale: 'en',                   // 语言
  hideMessageBubble: false,       // 是否隐藏气泡
  enableFileUpload: true,         // 启用文件上传
  // ... 更多选项
}
```

#### `channelConfig` - 渠道配置
```javascript
{
  widgetColor: '#009CE0',         // 气泡颜色
  websiteName: 'PlantsIO',
  disableBranding: true,          // 禁用品牌标识
  // ... 更多选项
}
```

#### `bubbleAnimationsConfig` - 🎨 气泡动画配置

**这是关键配置！** 用于设置气泡动画效果：

```javascript
bubbleAnimationsConfig: {
  // 入场动画：气泡首次出现时播放（加载后 0.5 秒）
  intro_animation_url: 'https://d2yysiie7eha49.cloudfront.net/cat.gif',
  
  // 打开动画：气泡打开时播放
  open_animation_url: '',
  
  // 关闭动画：气泡关闭时播放
  close_animation_url: '',
}
```

**设置为 `null` 可禁用所有动画：**
```javascript
bubbleAnimationsConfig: null
```

### 配置预设

`config.js` 还包含一些预设配置，可以快速切换：

```javascript
presets.default      // 默认配置（带入场动画）
presets.noAnimation  // 无动画
presets.fullAnimation // 完整动画（需要填写真实 URL）
presets.darkTheme    // 深色主题
```

## 📁 文件结构

```
playground/iframe-helper/
├── README.md          # 本文档
├── config.js          # 🔧 配置文件（修改这里！）
├── index.html         # 父页面 - 测试控制台
└── main.js            # 父页面逻辑，调用 IFrameHelper

widget/
└── index.html         # Widget stub - 模拟真实 widget iframe

script/
└── playground-iframe.mjs  # Vite 开发服务器启动脚本
```

## 🎯 使用示例

### 示例 1: 启用入场动画

编辑 `config.js`：
```javascript
bubbleAnimationsConfig: {
  intro_animation_url: 'https://d2yysiie7eha49.cloudfront.net/cat.gif',
  open_animation_url: '',
  close_animation_url: '',
}
```

保存后点击"重新挂载"，气泡会在加载后 0.5 秒播放猫咪动画。

### 示例 2: 禁用动画

编辑 `config.js`：
```javascript
bubbleAnimationsConfig: null
```

保存后点击"重新挂载"，气泡将显示默认 SVG 图标。

### 示例 3: 更改颜色和位置

编辑 `config.js`：
```javascript
// widgetConfig 部分
position: 'left',  // 改为左侧

// channelConfig 部分
widgetColor: '#dc2626',  // 改为红色
```

保存后点击"重新挂载"即可看到效果。

## 🎮 使用说明

### 父页面（playground/iframe-helper/）

父页面提供了一个测试控制台，用于：

- **挂载 Widget**: 创建 IFrameHelper 实例并加载 widget iframe
- **重新挂载**: 清理旧的 widget DOM 并重新加载（支持热更新）
- **气泡控制**: 打开/关闭气泡、设置未读模式等
- **事件日志**: 实时显示所有 IFrameHelper 与 widget 之间的通信消息

### Widget Stub（widget/index.html）

Widget stub 模拟真实的 widget iframe，提供丰富的测试功能：

#### 📤 发送事件到父窗口
- **设置气泡文本**: 动态更改气泡显示的文本
- **发送 Postback**: 模拟用户操作回调
- **更新高度**: 测试 iframe 高度调整
- **显示未读**: 模拟未读消息通知
- **触发提示音**: 测试音频提醒

#### 🎨 气泡动画测试
- **启用入场动画**: 测试气泡入场动画效果
- **禁用动画**: 恢复默认静态气泡
- **更改颜色**: 随机切换气泡颜色

#### 💬 模拟会话
- **添加消息**: 模拟客服/用户消息
- **自定义消息**: 输入任意消息内容
- **消息日志**: 查看所有通信事件

## 🔧 工作原理

### 消息通信协议

父页面和 iframe 之间使用 `postMessage` API 进行通信，所有消息格式为：

```javascript
'chatwoot-widget:' + JSON.stringify({ event: 'eventName', ...data })
```

### 主要事件类型

#### iframe → 父页面
- `loaded`: widget 加载完成
- `setBubbleLabel`: 设置气泡文本
- `handleNotificationDot`: 更新未读消息数
- `setUnreadMode` / `resetUnreadMode`: 控制未读状态
- `updateIframeHeight`: 请求调整 iframe 高度
- `closeWindow`: 关闭 widget 窗口
- `playAudio`: 播放提示音
- `postback`: 用户操作回调

#### 父页面 → iframe
- `config-set`: 发送配置信息
- `toggle-open`: 气泡打开/关闭状态
- `toggle-close-button`: 移动端关闭按钮切换
- `change-url`: 页面路由变化通知
- `push-event`: 推送自定义事件

## 🧪 测试场景

### 1. 基本挂载流程
1. 页面自动挂载 widget
2. 观察日志中的 `loaded` 事件
3. Widget iframe 自动打开

### 2. 气泡交互测试
1. 点击"关闭气泡"，观察气泡关闭
2. 点击"打开气泡"，观察气泡打开
3. 在 widget iframe 中点击"关闭窗口"，观察父页面反应

### 3. 未读消息测试
1. 在 widget iframe 中点击"显示未读 (3)"
2. 观察父页面气泡显示未读标记
3. 点击父页面"重置未读"，观察未读标记消失

### 4. 动画测试
1. 在 widget iframe 中点击"启用入场动画"
2. 点击父页面"重新挂载"
3. 观察气泡动画效果

### 5. 热更新测试
1. 修改 `app/javascript/sdk/IFrameHelper.js` 代码
2. 点击父页面"重新挂载"按钮
3. Vite HMR 会自动更新代码，无需刷新页面

## 🎯 开发技巧

### 查看通信日志

所有 iframe 和父页面之间的通信都会在以下位置显示：
- 父页面：右侧"事件日志"面板
- Widget iframe：底部"消息日志"面板
- 浏览器控制台：查看完整的 console.log 输出

### 调试技巧

1. **打开浏览器开发者工具**: F12 或右键 → 检查
2. **查看 Console**: 所有事件都会同时输出到控制台
3. **查看 Network**: 观察 iframe 加载和资源请求
4. **使用 Vue DevTools**: 如果 widget 使用 Vue，可以查看组件状态

### 修改测试配置

在 `main.js` 中修改 `window.$chatwoot` 配置：

```javascript
window.$chatwoot = {
  position: 'right',        // 或 'left'
  hideMessageBubble: false, // true 隐藏气泡
  widgetStyle: 'standard',  // 或 'flat'
  darkMode: false,          // true 启用暗黑模式
  locale: 'en',             // 语言设置
  // ... 更多配置
};
```

### 添加自定义测试

在 `main.js` 中添加新的按钮事件处理：

```javascript
document.getElementById('myButton').addEventListener('click', () => {
  IFrameHelper.sendMessage('my-event', { data: 'test' });
  log('→ 发送自定义事件', 'info', { event: 'my-event' });
});
```

在 `widget/index.html` 中监听并响应：

```javascript
window.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data.replace('chatwoot-widget:', ''));
  if (msg.event === 'my-event') {
    // 处理自定义事件
    addLog('in', '收到自定义事件', msg);
  }
});
```

## 🐛 常见问题

### Widget 没有加载

1. 检查控制台是否有错误
2. 确认 Vite 开发服务器正在运行
3. 尝试刷新页面或点击"重新挂载"

### 热更新不生效

1. 检查 Vite HMR 是否正常工作
2. 手动刷新页面（Ctrl+R / Cmd+R）
3. 清理浏览器缓存

### 消息没有收到

1. 检查消息格式是否正确（必须以 `chatwoot-widget:` 开头）
2. 检查 JSON 格式是否有效
3. 查看控制台是否有 postMessage 错误

## 📚 相关文档

- [IFrameHelper.js 源码](../../app/javascript/sdk/IFrameHelper.js)
- [Bubble Helpers](../../app/javascript/sdk/bubbleHelpers.js)
- [Widget SDK 文档](https://www.chatwoot.com/docs/product/channels/live-chat/sdk/setup)

## 🤝 贡献

如果你发现问题或有改进建议：
1. 在 widget stub 中添加更多测试场景
2. 改进日志显示和 UI
3. 添加更多自动化测试用例

---

Happy testing! 🎉

