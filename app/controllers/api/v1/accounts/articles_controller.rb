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
    # Get the target locale from params
    target_locale = params[:target_locale]

    # Validate target locale
    render json: { error: 'Target locale is required' }, status: :unprocessable_entity and return unless target_locale.present?

    # Create a new article with translated content
    translated_article = @portal.articles.create!(
      title: translate_content(@article.title, target_locale),
      description: @article.description.present? ? translate_content(@article.description, target_locale) : nil,
      content: translate_content(@article.content, target_locale),
      author_id: @article.author_id,
      category_id: @article.category_id,
      locale: target_locale,
      status: @article.status
    )

    # Associate with the original article
    translated_article.associate_root_article(@article.associated_article_id || @article.id)

    render json: { payload: translated_article }, status: :ok
  end

  private

  def translate_content(content, target_locale)
    # Use the LLM service to translate content
    llm_service = Llm::BaseOpenAiService.new

    # Prepare the prompt for translation
    prompt = <<~PROMPT
      Translate the following content to #{target_locale}:

      #{content}
    PROMPT

    # Call the OpenAI API
    response = llm_service.send(:client).chat(parameters: {
      model: llm_service.instance_variable_get(:@model),
      messages: [{ role: 'user', content: prompt }],
      temperature: 0.3
    })

    # Extract the translated content from the response
    response.dig('choices', 0, 'message', 'content')
  end

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
