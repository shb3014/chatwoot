class Api::V1::Widget::ConfigsController < Api::V1::Widget::BaseController
  before_action :set_global_config
  before_action :detect_widget_locale, only: [:create]

  def create
    build_contact
    set_token
  end

  private

  def set_global_config
    @global_config = GlobalConfig.get('LOGO_THUMBNAIL', 'BRAND_NAME', 'WIDGET_BRAND_URL', 'INSTALLATION_NAME')
  end

  def set_contact
    @contact_inbox = @web_widget.inbox.contact_inboxes.find_by(
      source_id: auth_token_params[:source_id]
    )
    @contact = @contact_inbox&.contact
  end

  def build_contact
    return if @contact.present?

    @contact_inbox = @web_widget.create_contact_inbox(additional_attributes)
    @contact = @contact_inbox.contact
  end

  def set_token
    payload = { source_id: @contact_inbox.source_id, inbox_id: @web_widget.inbox.id }
    @token = ::Widget::TokenService.new(payload: payload).generate_token
  end

  def additional_attributes
    if @web_widget.inbox.account.feature_enabled?('ip_lookup')
      { created_at_ip: request.remote_ip }
    else
      {}
    end
  end

  def detect_widget_locale
    # Priority: URL param > Help Center cookie > Browser Accept-Language > Account default
    # Check help center cookie first since users set their preference there
    url_locale = params[:locale]
    help_center_locale = cookies[:help_center_locale]
    browser_locale = locale_from_browser_for_widget
    account_locale = @web_widget.account.locale

    Rails.logger.info "[Widget API] Locale detection - URL: #{url_locale}, HelpCenter: #{help_center_locale}, Browser: #{browser_locale}, Account: #{account_locale}"

    detected_locale = url_locale || help_center_locale || browser_locale || account_locale
    @widget_locale = validate_widget_locale(detected_locale)

    Rails.logger.info "[Widget API] Final locale: #{@widget_locale}"
  end

  def locale_from_browser_for_widget
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
    locales.find { |locale| widget_supports_locale?(locale) }
  end

  def widget_supports_locale?(locale)
    return false if locale.blank?

    # Get available locales from I18n (widget supports all Chatwoot locales)
    available_locales = I18n.available_locales.map(&:to_s)

    # Check exact match
    return true if available_locales.include?(locale)

    # Check base language match (e.g., zh_CN -> zh)
    locale_base = locale.split('_').first
    available_locales.include?(locale_base)
  end

  def validate_widget_locale(locale)
    return @web_widget.account.locale if locale.blank?

    available_locales = I18n.available_locales.map(&:to_s)

    # Check exact match
    return locale if available_locales.include?(locale)

    # Check base language match (e.g., zh_CN -> zh)
    locale_base = locale.split('_').first
    return locale_base if available_locales.include?(locale_base)

    # Fall back to account default
    @web_widget.account.locale
  end
end
