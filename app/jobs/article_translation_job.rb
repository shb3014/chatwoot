class ArticleTranslationJob < ApplicationJob
  queue_as :low

  def perform(article_id, target_locale, user_id)
    Rails.logger.info "[ArticleTranslationJob] Starting translation for Article #{article_id} to #{target_locale}"

    article = Article.find(article_id)
    user = User.find(user_id)

    Rails.logger.info "[ArticleTranslationJob] Initializing service..."
    service = Llm::ArticleTranslationService.new(article, target_locale)

    Rails.logger.info "[ArticleTranslationJob] Calling AI service..."
    translated_data = service.translate

    if translated_data.nil?
      Rails.logger.error "[ArticleTranslationJob] Translation failed or returned nil"
      return
    end

    Rails.logger.info "[ArticleTranslationJob] Translation successful, saving article..."

    target_category = article.portal.categories.find_by(slug: article.category&.slug, locale: target_locale)
    root_article_id = article.associated_article_id || article.id
    existing_article = article.portal.articles.find_by(associated_article_id: root_article_id, locale: target_locale)
    existing_article ||= article if article.locale == target_locale

    article_attributes = {
      title: translated_data[:title],
      content: translated_data[:content],
      description: translated_data[:description],
      locale: target_locale,
      category_id: target_category&.id,
      associated_article_id: root_article_id,
      author_id: user.id,
      account_id: article.portal.account_id,
      portal_id: article.portal.id
    }

    if existing_article
      existing_article.update!(article_attributes.except(:associated_article_id, :account_id, :portal_id))
      Rails.logger.info "[ArticleTranslationJob] Updated existing article #{existing_article.id}"
    else
      translated_article = article.portal.articles.create!(article_attributes)
      translated_article.draft!
      Rails.logger.info "[ArticleTranslationJob] Created new article #{translated_article.id}"
    end
  rescue StandardError => e
    Rails.logger.error "[ArticleTranslationJob] Failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    raise e
  end
end

