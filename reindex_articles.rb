# Usage: RAILS_ENV=production bundle exec rails runner reindex_articles.rb

puts "=== Starting Article Re-indexing ==="

# 找出所有已发布且不是草稿的文章
articles = Article.where(status: :published)
total = articles.count
puts "Found #{total} published articles."

articles.find_each.with_index do |article, index|
  puts "[#{index + 1}/#{total}] Checking Article #{article.id} (#{article.title})..."

  # 检查是否已有向量
  if article.article_embeddings.exists?
    puts "  - Skipping: Embeddings already exist."
    next
  end

  puts "  - MISSING! Triggering embedding generation..."

  begin
    # 优先使用系统原生的 AI 关键词生成逻辑（保持与现有数据一致）
    # 注意：方法名在源码中拼写为 seach (缺少 r)，这里需保持一致
    if article.respond_to?(:generate_and_save_article_seach_terms)
      puts "  - Triggering AI to generate search terms..."
      article.generate_and_save_article_seach_terms
      puts "  - Success: Search terms generated."
    else
      # 如果没有企业版功能或方法不存在，回退到使用 标题+描述
      # 避免使用全文导致 term 过长影响检索效果
      puts "  - Fallback: Using Title + Description."
      embedding_record = ArticleEmbedding.find_or_initialize_by(article: article)
      embedding_record.term = "#{article.title} #{article.description}".strip
      embedding_record.save!
      puts "  - Success: Fallback term saved."
    end

  rescue => e
    puts "  - AI/System Error: #{e.message}"

    # 如果 AI 调用失败（如 API Key 问题），降级处理
    begin
      puts "  - Fallback: Using Title + Description due to error."
      embedding_record = ArticleEmbedding.find_or_initialize_by(article: article)
      embedding_record.term = "#{article.title} #{article.description}".strip
      embedding_record.save!
      puts "  - Success: Fallback term saved."
    rescue => e2
      puts "  - CRITICAL ERROR: #{e2.message}"
    end
  end
end

puts "\n=== Re-indexing process completed! ==="
puts "Please wait a few minutes for the background jobs to finish processing."
