class Public::Api::V1::Portals::BaseController < PublicController
  include SwitchLocale

  before_action :show_plain_layout
  before_action :set_color_scheme
  before_action :set_global_config
  around_action :set_locale
  after_action :allow_iframe_requests

  private

  def show_plain_layout
    @is_plain_layout_enabled = params[:show_plain_layout] == 'true'
  end

  def set_color_scheme
    @theme_from_params = params[:theme] if %w[dark light].include?(params[:theme])
  end

  def portal
    # 如果使用自定义域名，通过域名查找 portal
    if !DomainHelper.chatwoot_domain?(request.host)
      @portal ||= Portal.find_by!(custom_domain: request.host, archived: false)
    else
      # 否则通过 slug 查找
      @portal ||= Portal.find_by!(slug: params[:slug], archived: false)
    end
    # Priority: URL param > Cookie > Portal default
    @selected_locale = params[:locale] || cookies[:help_center_locale] || @portal.default_locale
    @locale = @selected_locale
    @portal
  end

  def set_locale(&)
    switch_locale_with_portal(&) if params[:locale].present?
    switch_locale_with_article(&) if params[:article_slug].present?

    yield
  end

  def switch_locale_with_portal(&)
    @locale = validate_and_get_locale(params[:locale])
    @selected_locale = @locale
    
    # Save user's locale preference in a cookie with SameSite=None and Secure
    # so it's accessible in widget iframes
    cookie_options = {
      value: @locale,
      expires: 1.year.from_now
    }
    
    # Only set SameSite=None if on HTTPS (required for cross-site cookies)
    if request.ssl? || Rails.env.production?
      cookie_options[:same_site] = :none
      cookie_options[:secure] = true
    end
    
    cookies[:help_center_locale] = cookie_options

    I18n.with_locale(@locale, &)
  end

  def switch_locale_with_article(&)
    article = Article.find_by(slug: params[:article_slug])
    Rails.logger.info "Article: not found for slug: #{params[:article_slug]}"
    render_404 && return if article.blank?

    article_locale = if article.category.present?
                       article.category.locale
                     else
                       article.portal.default_locale
                     end
    @locale = validate_and_get_locale(article_locale)
    # Preserve user's selected locale from cookie or URL for the locale switcher widget
    # This ensures the switcher shows what the user selected, even if the article is in a different language
    @selected_locale = params[:locale] || cookies[:help_center_locale] || @locale
    I18n.with_locale(@locale, &)
  end

  def allow_iframe_requests
    response.headers.delete('X-Frame-Options') if @is_plain_layout_enabled
  end

  def render_404
    portal
    render 'public/api/v1/portals/error/404', status: :not_found
  end

  def set_global_config
    @global_config = GlobalConfig.get('LOGO_THUMBNAIL', 'BRAND_NAME', 'BRAND_URL', 'INSTALLATION_NAME')
  end
end
