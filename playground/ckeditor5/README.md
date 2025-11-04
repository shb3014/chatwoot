# CKEditor5 样式测试 Playground

这个 playground 用于测试和预览 Chatwoot 中 CKEditor5 的样式配置。

## 🚀 快速开始

```bash
pnpm playground:ckeditor5
```

或者使用 npm：

```bash
npm run playground:ckeditor5
```

浏览器会自动打开 `http://localhost:5174/playground/ckeditor5/`

## 📋 功能特性

- ✅ **实时预览**: 实时查看 CKEditor5 的 HTML 输出和渲染效果
- ✅ **样式测试**: 测试 Chatwoot 中使用的所有样式配置
- ✅ **主题切换**: 支持亮色/暗色主题切换
- ✅ **统计信息**: 实时显示字符数、单词数、段落数
- ✅ **工具测试**: 测试所有编辑器功能（粗体、斜体、链接、表格等）
- ✅ **高度调整**: 动态调整编辑器最小高度

## 🎯 主要功能

### 编辑器配置
- 调整最小高度（200px - 500px）
- 设置占位符文本
- 清空编辑器内容
- 加载示例内容

### 测试工具
- 插入图片、表格、列表、链接
- 应用标题样式（H1, H2, H3）
- 切换粗体、斜体
- 插入引用块
- 获取编辑器数据

### 实时反馈
- **HTML 输出**: 显示编辑器生成的原始 HTML 代码
- **内容预览**: 渲染后的实际显示效果
- **统计信息**: 字符数、单词数、段落数

## 🎨 样式说明

这个 playground 使用了与 Chatwoot 主应用相同的样式配置：

- **颜色变量**: 使用 Chatwoot 的主题色系统
- **边框样式**: 与主应用保持一致
- **按钮样式**: 匹配工具栏按钮的视觉效果
- **暗色模式**: 完整支持暗色主题

样式定义位于：
- `app/javascript/dashboard/components/widgets/CKEditor5/CKEditor5.vue`

## 🔧 自定义配置

编辑器配置与 Chatwoot 主应用保持一致：

```javascript
{
  licenseKey: 'GPL',
  placeholder: '开始输入内容...',
  language: 'zh-cn',
  toolbar: [
    'heading',
    '|',
    'bold', 'italic', 'link',
    '|',
    'bulletedList', 'numberedList',
    '|',
    'blockQuote', 'insertTable',
    '|',
    'imageUpload', 'mediaEmbed',
    '|',
    'undo', 'redo',
  ],
  // ... 更多配置
}
```

## 💡 使用场景

1. **样式调试**: 在修改 CKEditor5 样式前，先在 playground 中测试效果
2. **功能验证**: 验证编辑器的各项功能是否正常工作
3. **主题测试**: 测试亮色/暗色模式下的视觉效果
4. **内容测试**: 测试各种复杂内容的渲染效果

## 📝 注意事项

- 图片上传功能在此 playground 中使用占位符图片
- 实际的图片上传逻辑在主应用中通过 Vuex store 处理
- 此 playground 使用 **CDN 版本**的 CKEditor5，版本号与 package.json 保持一致

### ⚠️ CDN 版本的限制

**重要：** CDN 版本的 CKEditor5 Classic Build 是预编译的包，有以下限制：

1. **无法添加额外插件** - 不能通过 `<script>` 标签引入插件（如 ImageResize、特殊字符等）
2. **固定的功能集** - 只包含 Classic Build 预设的功能
3. **不支持自定义构建** - 无法修改工具栏或添加自定义插件

### 💡 如何使用高级功能

如果需要使用图片缩放、自定义插件等高级功能，需要：

1. 在项目中通过 **npm 安装** CKEditor5
2. 使用 CKEditor5 的 **自定义构建工具**
3. 在构建时配置所需的插件

Chatwoot 主项目就是这样做的，参考：
```bash
# package.json
"@ckeditor/ckeditor5-build-classic": "^44.3.0",
"@ckeditor/ckeditor5-vue": "^7.3.0",

# app/javascript/dashboard/components/widgets/CKEditor5/CKEditor5.vue
# 使用 npm 版本，支持完整配置和自定义上传适配器
```

## 🔗 相关文件

- 主应用 CKEditor5 组件: `app/javascript/dashboard/components/widgets/CKEditor5/CKEditor5.vue`
- Playground HTML: `playground/ckeditor5/index.html`
- 启动脚本: `script/playground-ckeditor5.mjs`
- Package 配置: `package.json` (playground:ckeditor5 命令)

## 📚 文档参考

- [CKEditor5 官方文档](https://ckeditor.com/docs/ckeditor5/latest/)
- [Chatwoot CKEditor5 实现文档](../../CKEDITOR5_IMPLEMENTATION.md)

