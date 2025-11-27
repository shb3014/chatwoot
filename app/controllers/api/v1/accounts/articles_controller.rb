class Api::V1::Accounts::ArticlesController < Api::V1::Accounts::BaseController
  before_action :portal
  before_action :check_authorization
  before_action :fetch_article, except: [:index, :create, :reorder]
  before_action :set_current_page, only: [:index]

  def index
    @portal_articles = @portal.articles

    set_article_count

    @articles = @articles.search(list_params)

    @articles = if list_params[:category_slug].present?
                  @articles.order_by_position.page(@current_page)
                else
                  @articles.order_by_updated_at.page(@current_page)
                end
  end

  def show; end
  def edit; end

  def create
    @article = @portal.articles.create!(article_params)
    @article.associate_root_article(article_params[:associated_article_id])
    @article.draft!
    render json: { error: @article.errors.messages }, status: :unprocessable_entity and return unless @article.valid?
  end

  def update
    @article.update!(article_params) if params[:article].present?
    render json: { error: @article.errors.messages }, status: :unprocessable_entity and return unless @article.valid?
  end

  def destroy
    @article.destroy!
    head :ok
  end

  def reorder
    Article.update_positions(params[:positions_hash])
    head :ok
  end

  def translate
    target_locale = params[:target_locale]
    render json: { error: 'Target locale is required' }, status: :unprocessable_entity and return if target_locale.blank?

    service = Llm::ArticleTranslationService.new(@article, target_locale)
    translated_data = service.translate

    render json: { error: 'Translation failed' }, status: :unprocessable_entity and return if translated_data.nil?

    target_category = @portal.categories.find_by(slug: @article.category&.slug, locale: target_locale)
    root_article_id = @article.associated_article_id || @article.id
    existing_article = @portal.articles.find_by(associated_article_id: root_article_id, locale: target_locale)
    existing_article ||= @article if @article.locale == target_locale

    article_attributes = {
      title: translated_data[:title],
      content: translated_data[:content],
      description: translated_data[:description],
      locale: target_locale,
      category_id: target_category&.id,
      associated_article_id: root_article_id,
      author_id: Current.user.id,
      account_id: @portal.account_id,
      portal_id: @portal.id
    }

    if existing_article
      existing_article.update!(article_attributes.except(:associated_article_id, :account_id, :portal_id))
      @translated_article = existing_article
    else
      @translated_article = @portal.articles.create!(article_attributes)
      @translated_article.draft!
    end

    render json: @translated_article
  end

  private

  def set_article_count
    # Search the params without status and author_id, use this to
    # compute mine count published draft etc
    base_search_params = list_params.except(:status, :author_id)
    @articles = @portal_articles.search(base_search_params)

    @articles_count = @articles.count
    @mine_articles_count = @articles.search_by_author(Current.user.id).count
    @published_articles_count = @articles.published.count
    @draft_articles_count = @articles.draft.count
    @archived_articles_count = @articles.archived.count
  end

  def fetch_article
    @article = @portal.articles.find(params[:id])
  end

  def portal
    @portal ||= Current.account.portals.find_by!(slug: params[:portal_id])
  end

  def article_params
    params.require(:article).permit(
      :title, :slug, :position, :content, :description, :category_id, :author_id, :associated_article_id, :status,
      :locale, meta: [:title,
                      :description,
                      { tags: [] }]
    )
  end

  def list_params
    params.permit(:locale, :query, :page, :category_slug, :status, :author_id)
  end

  def set_current_page
    @current_page = params[:page] || 1
  end
end
