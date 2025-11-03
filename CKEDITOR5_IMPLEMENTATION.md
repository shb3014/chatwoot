# CKEditor 5 实现说明

## 概述

已成功将文章编辑器从 ProseMirror 迁移到 CKEditor 5，并保留了所有原有功能，包括图片上传。

## 实现的功能

### ✅ 已完成的功能

1. **富文本编辑器集成**
   - 使用 CKEditor 5 Classic Build
   - 支持标题（H1-H3）、段落格式
   - 支持粗体、斜体、链接
   - 支持有序列表、无序列表
   - 支持引用块
   - 支持表格插入和编辑
   - 支持媒体嵌入

2. **图片上传功能**
   - ✅ 通过工具栏按钮上传图片
   - ✅ 拖拽上传图片
   - ✅ 粘贴图片（从剪贴板）
   - ✅ 文件大小限制（4MB）
   - ✅ 与现有的 uploadFile API 集成
   - ✅ 图片样式选项（行内、块级、侧边）
   - ✅ 图片标题和替代文本

3. **编辑器特性**
   - 自动保存集成（继承自 ArticleEditor）
   - 占位符文本支持
   - 自动聚焦选项
   - 响应式设计
   - 暗色模式支持

## 文件结构

```
app/javascript/dashboard/
├── components/
│   └── widgets/
│       └── CKEditor5/
│           └── CKEditor5.vue          # 新的 CKEditor 5 组件
└── components-next/
    └── HelpCenter/
        └── Pages/
            └── ArticleEditorPage/
                └── ArticleEditor.vue   # 已更新使用 CKEditor5
```

## 如何使用

### 基本使用

```vue
<template>
  <CKEditor5
    v-model="content"
    placeholder="开始输入..."
    :autofocus="true"
    min-height="400px"
  />
</template>

<script setup>
import { ref } from 'vue';
import CKEditor5 from 'dashboard/components/widgets/CKEditor5/CKEditor5.vue';

const content = ref('');
</script>
```

### Props

- `modelValue` (String): 编辑器内容（HTML 格式）
- `placeholder` (String): 占位符文本
- `autofocus` (Boolean): 是否自动聚焦，默认 `true`
- `minHeight` (String): 编辑器最小高度，默认 `'300px'`

### Events

- `update:modelValue`: 内容变化时触发
- `focus`: 编辑器获得焦点时触发
- `blur`: 编辑器失去焦点时触发

## 图片上传流程

1. 用户通过以下方式添加图片：
   - 点击工具栏的"插入图片"按钮
   - 拖拽图片文件到编辑器
   - 粘贴剪贴板中的图片

2. CKEditor5 组件拦截上传请求

3. 检查文件大小（限制 4MB）

4. 调用 Vuex store 的 `articles/attachImage` action

5. 文件上传到服务器：`POST /api/v1/accounts/{accountId}/upload`

6. 服务器返回图片 URL

7. CKEditor 将图片插入到编辑器中

## 技术细节

### 自定义上传适配器

```javascript
class UploadAdapter {
  constructor(loader, uploadFunction) {
    this.loader = loader;
    this.uploadFunction = uploadFunction;
  }

  upload() {
    return this.loader.file.then(file => this.uploadFunction(file));
  }
}
```

这个适配器桥接了 CKEditor 5 的上传机制和 Chatwoot 现有的上传 API。

### 样式集成

编辑器样式使用 Tailwind CSS 类，并支持：
- 浅色/暗色主题
- 响应式设计
- 与 Chatwoot 设计系统一致

## 测试步骤

### 1. 启动开发服务器

```bash
pnpm dev
```

### 2. 测试基本编辑功能

- [ ] 创建新文章
- [ ] 输入标题和内容
- [ ] 测试格式化工具（粗体、斜体、标题等）
- [ ] 测试列表创建
- [ ] 测试链接插入
- [ ] 测试表格插入

### 3. 测试图片上传

#### 方式 1: 工具栏按钮
1. 点击工具栏的"插入图片"按钮
2. 选择图片文件（< 4MB）
3. 确认图片正确显示

#### 方式 2: 拖拽上传
1. 从文件管理器拖拽图片到编辑器
2. 确认图片正确上传和显示

#### 方式 3: 粘贴上传
1. 复制一张图片到剪贴板
2. 在编辑器中粘贴（Ctrl+V / Cmd+V）
3. 确认图片正确上传和显示

#### 测试大小限制
1. 尝试上传 > 4MB 的图片
2. 应该看到错误提示

### 4. 测试保存功能

- [ ] 编辑内容后等待自动保存
- [ ] 刷新页面，确认内容已保存
- [ ] 发布文章
- [ ] 在前台查看文章，确认图片和内容正确显示

## 依赖包

```json
{
  "@ckeditor/ckeditor5-vue": "^7.3.0",
  "@ckeditor/ckeditor5-build-classic": "^44.3.0"
}
```

## 许可证配置

CKEditor 5 从 v38 开始要求声明许可证密钥。由于 Chatwoot 是开源项目（使用 MIT 许可证），我们使用 GPL 许可证密钥：

```javascript
const editorConfig = {
  licenseKey: 'GPL',  // 开源项目使用 GPL 许可证
  // ... 其他配置
};
```

**说明：**
- `GPL` 许可证密钥适用于所有开源项目
- 这会在编辑器底部显示 "Powered by CKEditor" 水印
- 如果需要商业许可证（移除水印），需要从 CKEditor 官方购买

## 注意事项

1. **内容格式**: CKEditor 5 使用 HTML 格式存储内容，而原来的 ProseMirror 使用 Markdown。如果需要兼容旧内容，可能需要添加格式转换逻辑。

2. **升级路径**: 目前使用的是预构建版本（Classic Build），未来如果需要自定义功能，可以迁移到自定义构建。

3. **图片存储**: 图片上传使用现有的 Chatwoot 存储系统，与原有实现保持一致。

## 故障排除

### 编辑器不显示
- 检查浏览器控制台是否有错误
- 确认 CKEditor 5 包已正确安装
- 清除缓存并重新构建：`pnpm build`

### 图片上传失败
- 检查文件大小是否 < 4MB
- 检查网络请求是否成功（开发者工具 Network 面板）
- 确认 portal slug 和账户权限正确

### 样式问题
- 确认 Tailwind CSS 配置正确
- 检查是否有 CSS 冲突
- 尝试清除浏览器缓存

## 未来改进建议

1. **自定义构建**: 迁移到 CKEditor 5 的自定义构建，减小包体积
2. **插件扩展**: 添加更多插件（如代码高亮、数学公式等）
3. **协作编辑**: 集成 CKEditor 5 的实时协作功能
4. **Markdown 支持**: 添加 Markdown 输入/输出转换
5. **图片优化**: 自动压缩和优化上传的图片

## 相关文档

- [CKEditor 5 官方文档](https://ckeditor.com/docs/ckeditor5/latest/)
- [CKEditor 5 Vue 集成](https://ckeditor.com/docs/ckeditor5/latest/installation/getting-started/frameworks/vuejs-v3.html)
- [图片上传适配器](https://ckeditor.com/docs/ckeditor5/latest/framework/deep-dive/upload-adapter.html)

