class ArticleTranslationJob < ApplicationJob
  queue_as :low

  def perform(article_id, target_locale, user_id)
    article = Article.find(article_id)
    user = User.find(user_id)
    service = Llm::ArticleTranslationService.new(article, target_locale)
    translated_data = service.translate

    return if translated_data.nil?

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
    else
      translated_article = article.portal.articles.create!(article_attributes)
      translated_article.draft!
    end
  end
end

