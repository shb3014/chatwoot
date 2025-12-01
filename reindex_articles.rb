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

  # 创建占位记录并触发 Job
  # 注意：ArticleEmbedding 通常由 Article 模型的回调管理，但为了强制生成，
  # 我们直接模拟这一过程。

  # 这里我们直接调用 Job 的逻辑，或者手动创建 embedding 记录来触发回调
  begin
    # 尝试先创建一个空的 embedding 记录关联文章
    # 这里的 term 必须非空，否则模型校验可能不过
    embedding_record = ArticleEmbedding.find_or_initialize_by(article: article)
    embedding_record.term = article.content # 或者切片后的内容，这里简单起见用全文

    # 如果是新记录，保存会触发 after_commit 回调 -> 触发 Job
    if embedding_record.new_record? || embedding_record.embedding.nil?
      embedding_record.save!
      puts "  - Job queued successfully."
    else
       # 如果记录存在但没向量，强制重新跑 Job
       Captain::Llm::UpdateEmbeddingJob.perform_later(embedding_record, article.content)
       puts "  - Job queued (forced update)."
    end

  rescue => e
    puts "  - ERROR: #{e.message}"
  end
end

puts "\n=== Re-indexing process completed! ==="
puts "Please wait a few minutes for the background jobs to finish processing."
