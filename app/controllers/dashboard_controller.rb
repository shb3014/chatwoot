class DashboardController < ActionController::Base
  include SwitchLocale

  before_action :set_application_pack
  before_action :set_global_config
  before_action :set_dashboard_scripts
  around_action :switch_locale
  before_action :ensure_installation_onboarding, only: [:index]
  before_action :render_hc_if_custom_domain, only: [:index]
  before_action :ensure_html_format
  layout 'vueapp'

  def index; end

  private

  def ensure_html_format
    render json: { error: 'Please use API routes instead of dashboard routes for JSON requests' }, status: :not_acceptable if request.format.json?
  end

  def set_global_config
    @global_config = GlobalConfig.get(
      'LOGO', 'LOGO_DARK', 'LOGO_THUMBNAIL',
      'INSTALLATION_NAME',
      'WIDGET_BRAND_URL', 'TERMS_URL',
      'BRAND_URL', 'BRAND_NAME',
      'PRIVACY_URL',
      'DISPLAY_MANIFEST',
      'CREATE_NEW_ACCOUNT_FROM_DASHBOARD',
      'CHATWOOT_INBOX_TOKEN',
      'API_CHANNEL_NAME',
      'API_CHANNEL_THUMBNAIL',
      'ANALYTICS_TOKEN',
      'DIRECT_UPLOADS_ENABLED',
      'HCAPTCHA_SITE_KEY',
      'LOGOUT_REDIRECT_LINK',
      'DISABLE_USER_PROFILE_UPDATE',
      'DEPLOYMENT_ENV',
      'INSTALLATION_PRICING_PLAN'
    ).merge(app_config)
  end

  def set_dashboard_scripts
    @dashboard_scripts = sensitive_path? ? nil : GlobalConfig.get_value('DASHBOARD_SCRIPTS')
  end

  def ensure_installation_onboarding
    redirect_to '/installation/onboarding' if ::Redis::Alfred.get(::Redis::Alfred::CHATWOOT_INSTALLATION_ONBOARDING)
  end

  def render_hc_if_custom_domain
    domain = request.host
    return if domain == URI.parse(ENV.fetch('FRONTEND_URL', '')).host

    @portal = Portal.find_by(custom_domain: domain)
    return unless @portal

    # Check if locale is in the URL path (e.g., /en, /zh)
    locale_from_path = extract_locale_from_path
    
    if locale_from_path.present?
      # User has explicitly navigated to a locale path, use it
      @locale = validate_portal_locale(locale_from_path)
      @selected_locale = @locale
      # Save the locale so widget can access it
      set_help_center_locale_cookie(@locale)
    else
      # No locale in URL, detect and redirect
      detected_locale = detect_user_locale_for_portal(@portal)
      Rails.logger.info "[HelpCenter] DashboardController redirecting to locale: #{detected_locale}"
      # Set cookie before redirect so widget can access it
      set_help_center_locale_cookie(detected_locale)
      redirect_to "/#{detected_locale}" and return
    end
    
    render 'public/api/v1/portals/show', layout: 'portal', portal: @portal and return
  end

  def extract_locale_from_path
    # Extract locale from paths like /en, /zh, /en/articles, etc.
    path_parts = request.path.split('/').reject(&:blank?)
    return nil if path_parts.empty?
    
    # First path segment might be a locale
    potential_locale = path_parts.first
    
    # Check if it looks like a locale code (e.g., en, zh, pt_BR, zh_CN)
    potential_locale if potential_locale.match?(/^[a-z]{2,3}(_[A-Z]{2})?$/i)
  end

  def detect_user_locale_for_portal(portal)
    # Priority: Cookie > Browser Accept-Language > Portal default
    cookie_locale = cookies[:help_center_locale]
    browser_locale = locale_from_browser_for_portal(portal)
    default_locale = portal.default_locale
    
    Rails.logger.info "[HelpCenter] Locale detection - Cookie: #{cookie_locale}, Browser: #{browser_locale}, Default: #{default_locale}"
    
    locale = cookie_locale || browser_locale || default_locale
    validate_portal_locale(locale)
  end

  def locale_from_browser_for_portal(portal)
    return nil unless request.headers['HTTP_ACCEPT_LANGUAGE'].present?

    accept_language = request.headers['HTTP_ACCEPT_LANGUAGE']
    
    # Parse and sort by quality value
    locales = accept_language.split(',').map do |lang|
      locale, quality = lang.strip.split(';q=')
      quality = quality ? quality.to_f : 1.0
      normalized_locale = locale.strip.tr('-', '_')
      [normalized_locale, quality]
    end.sort_by { |_, q| -q }.map(&:first)

    # Find first supported locale
    locales.find { |locale| portal_supports_locale?(portal, locale) }
  end

  def portal_supports_locale?(portal, locale)
    return false if locale.blank?

    portal_config = portal.config || {}
    allowed_locales = portal_config['allowed_locales'] || []
    return true if allowed_locales.empty?

    locale_base = locale.split('_').first
    allowed_locales.include?(locale) || allowed_locales.include?(locale_base)
  end

  def validate_portal_locale(locale)
    return @portal.default_locale if locale.blank?

    portal_config = @portal.config || {}
    allowed_locales = portal_config['allowed_locales'] || []
    return locale if allowed_locales.empty?

    return locale if allowed_locales.include?(locale)

    locale_base = locale.split('_').first
    return locale_base if allowed_locales.include?(locale_base)

    @portal.default_locale
  end

  def set_help_center_locale_cookie(locale)
    # Set cookie with SameSite=None and Secure so it's accessible in widget iframes
    # This allows the widget to read the user's help center language preference
    # Note: SameSite=None requires Secure=true (HTTPS)
    cookie_options = {
      value: locale,
      expires: 1.year.from_now
    }
    
    # Only set SameSite=None if on HTTPS (required for cross-site cookies)
    if request.ssl? || Rails.env.production?
      cookie_options[:same_site] = :none
      cookie_options[:secure] = true
    end
    
    cookies[:help_center_locale] = cookie_options
  end

  def app_config
    {
      APP_VERSION: Chatwoot.config[:version],
      VAPID_PUBLIC_KEY: VapidService.public_key,
      ENABLE_ACCOUNT_SIGNUP: GlobalConfigService.load('ENABLE_ACCOUNT_SIGNUP', 'false'),
      FB_APP_ID: GlobalConfigService.load('FB_APP_ID', ''),
      INSTAGRAM_APP_ID: GlobalConfigService.load('INSTAGRAM_APP_ID', ''),
      FACEBOOK_API_VERSION: GlobalConfigService.load('FACEBOOK_API_VERSION', 'v18.0'),
      WHATSAPP_APP_ID: GlobalConfigService.load('WHATSAPP_APP_ID', ''),
      WHATSAPP_CONFIGURATION_ID: GlobalConfigService.load('WHATSAPP_CONFIGURATION_ID', ''),
      IS_ENTERPRISE: ChatwootApp.enterprise?,
      AZURE_APP_ID: GlobalConfigService.load('AZURE_APP_ID', ''),
      GIT_SHA: GIT_HASH
    }
  end

  def set_application_pack
    @application_pack = if request.path.include?('/auth') || request.path.include?('/login')
                          'v3app'
                        else
                          'dashboard'
                        end
  end

  def sensitive_path?
    # dont load dashboard scripts on sensitive paths like password reset
    sensitive_paths = [edit_user_password_path].freeze

    # remove app prefix
    current_path = request.path.gsub(%r{^/app}, '')

    sensitive_paths.include?(current_path)
  end
end
