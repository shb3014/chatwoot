class Public::Api::V1::Portals::ArticlesController < Public::Api::V1::Portals::BaseController
  before_action :ensure_custom_domain_request, only: [:show, :index]
  before_action :portal
  before_action :set_category, except: [:index, :show, :tracking_pixel]
  before_action :set_article, only: [:show]
  layout 'portal'

  def index
    @articles = @portal.articles.published.includes(:category, :author)

    @articles = @articles.where(locale: permitted_params[:locale]) if permitted_params[:locale].present?

    @articles_count = @articles.count

    search_articles
    order_by_sort_param
    limit_results
  end

  def show
    @og_image_url = helpers.set_og_image_url(@portal.name, @article.title)
  end

  def tracking_pixel
    @article = @portal.articles.find_by(slug: permitted_params[:article_slug])
    return head :not_found unless @article

    @article.increment_view_count if @article.published?

    # Serve the 1x1 tracking pixel with 24-hour private cache
    # Private cache bypasses CDN but allows browser caching to prevent duplicate views from same user
    expires_in 24.hours, public: false
    response.headers['Content-Type'] = 'image/png'

    pixel_path = Rails.public_path.join('assets/images/tracking-pixel.png')
    send_file pixel_path, type: 'image/png', disposition: 'inline'
  end

  private

  def limit_results
    return if list_params[:per_page].blank?

    per_page = [list_params[:per_page].to_i, 100].min
    per_page = 25 if per_page < 1
    @articles = @articles.page(list_params[:page]).per(per_page)
  end

  def search_articles
    @articles = @articles.search(list_params) if list_params.present?
  end

  def order_by_sort_param
    @articles = if list_params[:sort].present? && list_params[:sort] == 'views'
                  @articles.order_by_views
                else
                  @articles.order_by_position
                end
  end

  def set_article
    @article = @portal.articles.find_by(slug: permitted_params[:article_slug])
    @parsed_content = render_article_content(@article.content)
  end

  def set_category
    return if permitted_params[:category_slug].blank?

    @category = @portal.categories.find_by!(
      slug: permitted_params[:category_slug],
      locale: permitted_params[:locale]
    )
  end

  def list_params
    params.permit(:query, :locale, :sort, :status, :page, :per_page)
  end

  def permitted_params
    params.permit(:slug, :category_slug, :locale, :id, :article_slug)
  end

  def render_article_content(content)
    return '' if content.blank?

    # 检测内容格式：如果包含 HTML 标签，则视为 HTML 格式
    # CKEditor 5 存储 HTML，旧编辑器存储 Markdown
    if content.strip.start_with?('<') || content.include?('<p>') || content.include?('<h1>') || content.include?('<h2>')
      # HTML 格式 - 使用 sanitize 清理并返回
      ActionController::Base.helpers.sanitize(
        content,
        tags: %w[
          p br strong em u s a img h1 h2 h3 h4 h5 h6
          ul ol li blockquote pre code table thead tbody tr th td
          figure figcaption iframe
        ],
        attributes: {
          'a' => %w[href title target rel],
          'img' => %w[src alt title width height],
          'iframe' => %w[src width height frameborder allowfullscreen],
          'table' => %w[border cellpadding cellspacing],
          'th' => %w[colspan rowspan],
          'td' => %w[colspan rowspan],
        }
      ).html_safe
    else
      # Markdown 格式 - 使用现有的渲染器（向后兼容）
      ChatwootMarkdownRenderer.new(content).render_article
    end
  end
end

Public::Api::V1::Portals::ArticlesController.prepend_mod_with('Public::Api::V1::Portals::ArticlesController')
