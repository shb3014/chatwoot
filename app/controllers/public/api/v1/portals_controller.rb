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

    detected_locale = detect_user_locale
    
    Rails.logger.info "[HelpCenter] Redirecting to locale: #{detected_locale} for portal: #{@portal.slug}"
    
    # 如果是自定义域名，重定向到 /:locale
    # 否则重定向到标准路径 /hc/:slug/:locale
    if !DomainHelper.chatwoot_domain?(request.host) && @portal&.custom_domain.present?
      redirect_to("/#{detected_locale}") and return
    else
      redirect_to("/hc/#{@portal.slug}/#{detected_locale}") and return
    end
  end

  def detect_user_locale
    # Priority: Cookie > Browser Accept-Language > Portal default
    cookie_locale = cookies[:help_center_locale]
    browser_locale = locale_from_browser
    default_locale = @portal.default_locale
    
    Rails.logger.info "[HelpCenter] Locale detection - Cookie: #{cookie_locale}, Browser: #{browser_locale}, Default: #{default_locale}"
    
    locale = cookie_locale || browser_locale || default_locale
    
    # Ensure the locale is supported by the portal
    final_locale = supported_locale(locale)
    
    Rails.logger.info "[HelpCenter] Final locale: #{final_locale} (from: #{locale})"
    
    final_locale
  end

  def locale_from_browser
    return nil unless request.headers['HTTP_ACCEPT_LANGUAGE'].present?

    # Parse Accept-Language header (e.g., "en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7")
    accept_language = request.headers['HTTP_ACCEPT_LANGUAGE']
    
    # Extract locales with quality values, sort by quality (highest first)
    locales = accept_language.split(',').map do |lang|
      locale, quality = lang.strip.split(';q=')
      quality = quality ? quality.to_f : 1.0
      # Normalize locale format: en-US -> en_US, zh-CN -> zh_CN
      normalized_locale = locale.strip.tr('-', '_')
      [normalized_locale, quality]
    end.sort_by { |_, q| -q }.map(&:first)

    # Find the first locale that's supported by the portal
    locales.find { |locale| supported_locale?(locale) }
  end

  def supported_locale?(locale)
    return false if locale.blank?

    portal_config = @portal.config || {}
    allowed_locales = portal_config['allowed_locales'] || []
    
    # If no allowed_locales configured, accept any locale
    return true if allowed_locales.empty?

    # Check exact match or base language match (e.g., zh_CN -> zh)
    locale_base = locale.split('_').first
    allowed_locales.include?(locale) || allowed_locales.include?(locale_base)
  end

  def supported_locale(locale)
    return @portal.default_locale if locale.blank?

    # If portal config is nil or allowed_locales is not set, return the locale if it matches default
    # or just return the default locale
    portal_config = @portal.config || {}
    allowed_locales = portal_config['allowed_locales'] || []
    
    # If no allowed_locales configured, just use the locale as-is (portal might not have locale restrictions)
    return locale if allowed_locales.empty?

    # Check exact match
    return locale if allowed_locales.include?(locale)

    # Check base language match (e.g., zh_CN -> zh)
    locale_base = locale.split('_').first
    return locale_base if allowed_locales.include?(locale_base)

    # Fall back to portal default
    @portal.default_locale
  end
end
