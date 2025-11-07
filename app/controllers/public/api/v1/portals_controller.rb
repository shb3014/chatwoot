class Public::Api::V1::PortalsController < Public::Api::V1::Portals::BaseController
  before_action :ensure_custom_domain_request, only: [:show]
  before_action :portal
  before_action :redirect_to_portal_with_locale, only: [:show]
  layout 'portal'

  def show
    @og_image_url = helpers.set_og_image_url('', @portal.header_text)
  end

  def sitemap
    @help_center_url = @portal.custom_domain || ChatwootApp.help_center_root
    # if help_center_url does not contain a protocol, prepend it with https
    @help_center_url = "https://#{@help_center_url}" unless @help_center_url.include?('://')
  end

  private

  def portal
    # 使用 BaseController 的 portal 方法，它已经处理了自定义域名的情况
    super
  end

  def redirect_to_portal_with_locale
    return if params[:locale].present?

    # 如果是自定义域名，重定向到 /:locale
    # 否则重定向到标准路径 /hc/:slug/:locale
    if !DomainHelper.chatwoot_domain?(request.host) && @portal&.custom_domain.present?
      redirect_to "/#{@portal.default_locale}"
    else
      redirect_to "/hc/#{@portal.slug}/#{@portal.default_locale}"
    end
  end
end
