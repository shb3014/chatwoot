# Usage: bundle exec rails runner debug_article_embeddings.rb "你的搜索关键词" [article_id]

query = ARGV[0]
target_article_id = ARGV[1]

if query.blank?
  puts "Usage: bundle exec rails runner debug_article_embeddings.rb \"Your Search Query\" [article_id]"
  exit
end

puts "\n=== 1. Checking Embedding Service Config ==="
puts "Endpoint: #{InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value || 'Default (OpenAI)'}"
puts "Model: #{InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value || 'Default (gpt-4o-mini)'}"

puts "\n=== 2. Generating Embedding for Query: '#{query}' ==="
begin
  query_embedding = Captain::Llm::EmbeddingService.new.get_embedding(query)
  puts "✅ Embedding generated successfully (Vector length: #{query_embedding.length})"
rescue => e
  puts "❌ Failed to generate embedding: #{e.message}"
  exit
end

if target_article_id.present?
  puts "\n=== 3. Inspecting Specific Article (ID: #{target_article_id}) ==="
  article = Article.find_by(id: target_article_id)

  if article
    puts "Title: #{article.title}"
    puts "Locale: #{article.locale}"

    embeddings = ArticleEmbedding.where(article_id: article.id)
    puts "Chunk Count: #{embeddings.count}"

    if embeddings.any?
      puts "\nCalculating distances for each chunk:"
      embeddings.each_with_index do |ae, idx|
        # Manually calculate cosine distance if db function not available in script
        # But here we can use pgvector's distance function via SQL
        dist = ArticleEmbedding.where(id: ae.id)
                               .select("embedding <=> '#{query_embedding}' as dist")
                               .first.dist
        puts "  Chunk ##{idx + 1}: Distance = #{dist} | Term Preview: #{ae.term.truncate(50)}"
      end
    else
      puts "⚠️ No embeddings found for this article! (Job might have failed or not run)"
    end
  else
    puts "❌ Article not found"
  end
end

puts "\n=== 4. Performing Search (Top 5 Global) ==="
results = ArticleEmbedding.nearest_neighbors(:embedding, query_embedding, distance: 'cosine').limit(5)

results.each_with_index do |ae, i|
  article = ae.article
  dist = ArticleEmbedding.where(id: ae.id).select("embedding <=> '#{query_embedding}' as dist").first.dist
  puts "[#{i+1}] Distance: #{dist.round(4)} | Article ID: #{article.id} | Locale: #{article.locale} | Title: #{article.title}"
  puts "    Term: #{ae.term.truncate(80)}"
end

