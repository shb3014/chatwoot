# 聊天气泡动画功能实现指南

## 功能概述

实现了聊天气泡的 WebP 动画功能：
- **介绍动画**：气泡首次出现时播放的动画
- **悬停动画**：鼠标悬停在气泡上时从列表中随机播放的动画
- 动画配置可在 **Inbox 设置 > Widget Builder** 标签中管理

---

## 📝 手动执行数据库迁移

**⚠️ 重要**：由于数据库在远程服务器上，请手动执行以下迁移：

```ruby
# 文件位置: db/migrate/20251027000001_add_bubble_animations_to_channel_web_widgets.rb

class AddBubbleAnimationsToChannelWebWidgets < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_web_widgets, :bubble_animations_config, :jsonb, default: {}
  end
end
```

**执行命令**（在远程服务器上）：
```bash
bundle exec rails db:migrate
```

---

## 📂 修改的文件清单

### 1. **后端**

#### 数据库迁移
- ✅ `db/migrate/20251027000001_add_bubble_animations_to_channel_web_widgets.rb`
  - 添加 `bubble_animations_config` JSONB 字段

#### 模型
- ✅ `app/models/channel/web_widget.rb`
  - 添加 `bubble_animations_config` 到 `EDITABLE_ATTRS`
  - 支持 `intro_animation_url` 和 `hover_animation_urls` 配置

#### API 视图
- ✅ `app/views/api/v1/widget/configs/create.json.jbuilder`
  - 在 Widget API 响应中返回 `bubble_animations_config`
- ✅ `app/views/api/v1/models/_inbox.json.jbuilder`
  - 在 Dashboard Inbox API 响应中返回 `bubble_animations_config`

### 2. **前端 - Dashboard**

#### Widget Builder UI
- ✅ `app/javascript/dashboard/routes/dashboard/settings/inbox/WidgetBuilder.vue`
  - 添加动画配置表单
  - 支持添加/删除多个悬停动画 URL
  - 保存动画配置到后端

#### 国际化
- ✅ `app/javascript/dashboard/i18n/locale/en/inboxMgmt.json`
  - 添加动画配置相关的英文文本

### 3. **前端 - Widget SDK**

#### 气泡动画逻辑
- ✅ `app/javascript/sdk/bubbleHelpers.js`
  - 新增 `setupBubbleAnimations()` 函数
  - 实现介绍动画播放
  - 实现悬停时随机动画播放
  - 动画淡入淡出效果

#### SDK 集成
- ✅ `app/javascript/sdk/IFrameHelper.js`
  - 从 API 获取动画配置
  - 调用 `setupBubbleAnimations()` 初始化动画

---

## 🎨 使用方法

### 1. 在 Widget Builder 中配置动画

1. 登录 Chatwoot Dashboard
2. 进入 **Settings > Inboxes**
3. 选择一个 Website 类型的 Inbox
4. 切换到 **Widget Builder** 标签
5. 滚动到 **Bubble Animations** 部分
6. 配置动画：
   - **Intro Animation URL**: 输入 WebP 动画文件的 URL（例如：`https://example.com/intro.webp`）
   - **Hover Animation URLs**: 点击 "Add Hover Animation" 添加多个 WebP 动画 URL
7. 点击 **Update Widget Settings** 保存

### 2. 动画文件要求

- **格式**：WebP（推荐使用动画 WebP 格式）
- **大小**：建议不超过 500KB 以保证加载速度
- **尺寸**：建议 64x64 到 128x128 像素
- **托管**：需要托管在可公开访问的 URL（支持 HTTPS）

### 3. 动画行为

#### 介绍动画
- 气泡首次出现后 500ms 开始播放
- 默认播放 3 秒后自动消失
- 完成后恢复显示原有的 SVG 图标

#### 悬停动画
- 鼠标悬停在气泡上时触发
- 从配置的多个动画中随机选择一个播放
- 播放 2 秒后自动消失
- 动画播放期间再次悬停不会触发新动画（防止重叠）

---

## 🔧 技术细节

### 数据结构

**`bubble_animations_config` JSONB 字段结构**：
```json
{
  "intro_animation_url": "https://example.com/intro.webp",
  "hover_animation_urls": [
    "https://example.com/hover-1.webp",
    "https://example.com/hover-2.webp",
    "https://example.com/hover-3.webp"
  ]
}
```

### 前端实现

**动画元素样式**：
```css
#woot-bubble-animation {
  position: absolute;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  object-fit: cover;
  border-radius: inherit;
  pointer-events: none;
  opacity: 0;
  transition: opacity 0.3s ease;
}
```

**关键函数**：
- `createAnimationImage()`: 创建动画 img 元素
- `playAnimation(url, duration)`: 播放指定的动画
- `getRandomHoverAnimation()`: 从列表中随机选择动画
- `setupBubbleAnimations(config)`: 初始化动画配置

---

## 🧪 测试步骤

### 1. 后端测试

```bash
# 启动 Rails console
bundle exec rails console

# 测试数据保存
web_widget = Channel::WebWidget.last
web_widget.update(
  bubble_animations_config: {
    intro_animation_url: 'https://example.com/intro.webp',
    hover_animation_urls: ['https://example.com/hover.webp']
  }
)

# 验证数据
web_widget.reload.bubble_animations_config
```

### 2. 前端测试

1. **Widget Builder UI**：
   - 检查表单是否正常显示
   - 添加/删除悬停动画功能是否正常
   - 保存后刷新页面，检查配置是否正确加载

2. **Widget 动画**：
   - 在测试网站上安装 widget
   - 刷新页面，观察介绍动画是否播放
   - 鼠标悬停在气泡上，观察悬停动画是否随机播放

---

## 🎬 示例动画资源

您可以使用以下工具创建 WebP 动画：

1. **在线工具**：
   - [ezgif.com](https://ezgif.com/maker) - GIF 转 WebP
   - [CloudConvert](https://cloudconvert.com/) - 多格式转换

2. **命令行工具**：
```bash
# 使用 ffmpeg 创建动画 WebP
ffmpeg -i input.gif -vcodec libwebp -lossless 1 -q:v 100 output.webp

# 使用 cwebp (更多控制)
gif2webp input.gif -o output.webp
```

---

## 📊 性能优化建议

1. **压缩动画文件**：使用工具压缩 WebP 文件大小
2. **CDN 托管**：将动画文件托管在 CDN 上以提高加载速度
3. **延迟加载**：动画在需要时才加载，不影响页面初始加载
4. **缓存**：浏览器会自动缓存已加载的动画文件

---

## 🐛 故障排除

### 动画不显示

1. **检查 URL 是否可访问**：
   - 在浏览器中直接打开动画 URL
   - 确保 URL 支持 HTTPS 和跨域访问

2. **检查浏览器控制台**：
   - 查看是否有 CORS 错误
   - 查看是否有网络请求失败

3. **检查文件格式**：
   - 确保文件是 WebP 格式
   - 确保文件是动画 WebP（不是静态图片）

### 动画播放不流畅

1. **减小文件大小**：压缩动画文件
2. **降低动画复杂度**：减少帧数或分辨率
3. **使用 CDN**：提高下载速度

---

## 🚀 部署清单

在部署到生产环境前，请确保：

- [ ] 数据库迁移已在生产环境执行
- [ ] 前端资源已重新构建（`pnpm build`）
- [ ] Rails assets 已预编译（`RAILS_ENV=production bundle exec rails assets:precompile`）
- [ ] Chatwoot 服务已重启（`sudo systemctl restart chatwoot.target`）
- [ ] 动画文件已上传到 CDN 或可访问的服务器
- [ ] 在预生产环境测试所有功能
- [ ] 检查不同浏览器的兼容性
- [ ] 监控 API 响应时间（确保添加新字段不影响性能）
- [ ] 清除浏览器缓存验证更新（Ctrl+Shift+R）

### 生产环境部署命令

```bash
# 1. 执行数据库迁移
cd /path/to/chatwoot
RAILS_ENV=production bundle exec rails db:migrate

# 2. 安装依赖
pnpm install

# 3. 构建前端
NODE_ENV=production pnpm build

# 4. 预编译 assets
RAILS_ENV=production bundle exec rails assets:precompile

# 5. 重启服务
sudo systemctl restart chatwoot.target

# 6. 验证服务状态
sudo systemctl status chatwoot-web.1.service
```

---

## 📝 未来改进建议

1. **动画上传功能**：直接在 Widget Builder 中上传动画文件
2. **动画预览**：在配置表单中实时预览动画效果
3. **更多动画选项**：
   - 配置动画播放时长
   - 配置动画循环次数
   - 配置动画触发条件
4. **性能监控**：追踪动画加载时间和播放性能
5. **A/B 测试**：测试不同动画对用户互动的影响

---

## 📖 相关文档

- [Chatwoot Widget Builder 文档](https://www.chatwoot.com/docs/product/channels/live-chat/sdk/setup)
- [WebP 格式说明](https://developers.google.com/speed/webp)
- [Web Animations API](https://developer.mozilla.org/en-US/docs/Web/API/Web_Animations_API)

---

## 👨‍💻 技术支持

如有问题，请联系开发团队或在 GitHub 仓库中创建 Issue。

**实现日期**: 2025-10-27
**版本**: 1.0.0

