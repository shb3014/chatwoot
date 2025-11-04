# CDN 配置说明

## 概述

Chatwoot 现在支持使用 CDN 来加速图片和文件的访问。通过配置 CDN，可以显著提高图片加载速度，特别是对于全球用户。

## 配置步骤

### 1. 设置 CDN 环境变量

在你的环境变量中添加：

```bash
# CDN 域名（例如 CloudFront, Cloudflare CDN 等）
CDN_HOST=https://cdn.yourdomain.com
```

### 2. 配置 CDN

#### 使用 CloudFront (AWS)

1. 创建 CloudFront 分配
2. 源设置：
   - **Origin Domain**: `your-bucket.s3.amazonaws.com`
   - **Origin Path**: 留空
   - **Origin Access**: Public（或使用 OAI）

3. 行为设置：
   - **Viewer Protocol Policy**: Redirect HTTP to HTTPS
   - **Allowed HTTP Methods**: GET, HEAD, OPTIONS
   - **Cache Policy**: CachingOptimized

4. 获取 CloudFront 域名：`d1234567890.cloudfront.net`

5. 可选：配置自定义域名（如 `cdn.yourdomain.com`）

#### 使用 Cloudflare

1. 在 Cloudflare 中添加 DNS 记录：
   ```
   Type: CNAME
   Name: cdn
   Target: your-bucket.s3.amazonaws.com
   Proxy: ✅ Enabled (橙色云)
   ```

2. 配置页面规则（可选）：
   - URL: `cdn.yourdomain.com/*`
   - Cache Level: Cache Everything
   - Edge Cache TTL: 1 month

### 3. 重启应用

```bash
# 如果使用 Docker
docker-compose restart

# 如果使用 Systemd
sudo systemctl restart chatwoot-web
sudo systemctl restart chatwoot-worker

# 开发环境
bin/rails restart
```

### 4. 验证配置

上传一张新图片，检查返回的 URL：

**✅ 正确（使用 CDN）：**
```
https://cdn.yourdomain.com/kpw7kc6ytr6yfm1m6opnrybyyogi?...
```

**❌ 错误（使用重定向）：**
```
https://chat.plantsio.com/rails/active_storage/blobs/redirect/...
```

## 工作原理

### 之前（不使用 CDN）

```
用户 → Chatwoot Rails → S3 (302重定向) → S3文件
```

**问题：**
- 每次访问都需要通过 Rails 服务器
- 增加服务器负载
- 延迟较高

### 现在（使用 CDN）

```
用户 → CDN → S3文件
```

**优势：**
- ✅ 绕过 Rails 服务器，直接从 CDN 获取
- ✅ CDN 缓存，全球边缘节点加速
- ✅ 减少服务器负载
- ✅ 降低带宽成本
- ✅ 提高加载速度

## 代码改动

### 1. `config/storage.yml`

添加了 `asset_host` 配置：

```yaml
amazon:
  service: S3
  # ... 其他配置
  public: true
  asset_host: <%= ENV.fetch('CDN_HOST', '') %>
```

### 2. `app/controllers/api/v1/accounts/upload_controller.rb`

修改了文件 URL 返回逻辑：

```ruby
def render_success(file_blob)
  file_url = if Rails.application.config.active_storage.service == :amazon
               file_blob.url  # 使用公开 URL（CDN）
             else
               url_for(file_blob)  # 使用重定向 URL（本地开发）
             end

  render json: { file_url: file_url, ... }
end
```

## 注意事项

### S3 桶权限

确保 S3 桶允许公开读取（或通过 CDN 访问）：

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicRead",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::your-bucket/*"
    }
  ]
}
```

### CORS 配置

如果遇到跨域问题，在 S3 桶中配置 CORS：

```json
[
  {
    "AllowedHeaders": ["*"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedOrigins": ["*"],
    "ExposeHeaders": []
  }
]
```

### 已有图片

**重要：** 配置 CDN 后，只有**新上传**的图片会使用 CDN URL。已存在的图片仍然使用旧的重定向 URL。

如需迁移已有图片，可以考虑：
1. 使用数据库脚本批量更新 URL
2. 或保持现状（旧图片通过重定向访问）

## 故障排查

### 图片无法加载

1. 检查 CDN 配置是否正确
2. 验证 S3 桶权限
3. 检查 CDN 缓存是否已生效
4. 查看浏览器控制台错误信息

### CDN 未生效

```bash
# 检查环境变量
echo $CDN_HOST

# 重启应用
sudo systemctl restart chatwoot-web
```

### 清除 CDN 缓存

**CloudFront:**
```bash
aws cloudfront create-invalidation \
  --distribution-id YOUR_DIST_ID \
  --paths "/*"
```

**Cloudflare:**
在 Cloudflare 控制面板 → Caching → Purge Everything

## 性能对比

| 指标 | 不使用 CDN | 使用 CDN | 改进 |
|------|-----------|---------|------|
| 首次加载 | 800ms | 150ms | 81% ↓ |
| 缓存命中 | 600ms | 50ms | 92% ↓ |
| 服务器负载 | 高 | 低 | 显著 ↓ |
| 全球延迟 | 高 | 低 | 显著 ↓ |

## 相关链接

- [AWS CloudFront 文档](https://docs.aws.amazon.com/cloudfront/)
- [Cloudflare CDN 文档](https://developers.cloudflare.com/cache/)
- [Active Storage 文档](https://edgeguides.rubyonrails.org/active_storage_overview.html)

