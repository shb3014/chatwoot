# TODO : Delete this and associated spec once 'api/widget/config' end point is merged
class WidgetsController < ActionController::Base
  include WidgetHelper

  before_action :set_global_config
  before_action :set_web_widget
  before_action :ensure_account_is_active
  before_action :ensure_location_is_supported
  before_action :set_token
  before_action :set_contact
  before_action :build_contact
  before_action :detect_widget_locale
  after_action :allow_iframe_requests

  private

  def set_global_config
    @global_config = GlobalConfig.get('LOGO_THUMBNAIL', 'BRAND_NAME', 'WIDGET_BRAND_URL', 'DIRECT_UPLOADS_ENABLED', 'INSTALLATION_NAME')
  end

  def set_web_widget
    @web_widget = ::Channel::WebWidget.find_by!(website_token: permitted_params[:website_token])
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error('web widget does not exist')
    render json: { error: 'web widget does not exist' }, status: :not_found
  end

  def set_token
    @token = permitted_params[:cw_conversation]
    @auth_token_params = if @token.present?
                           ::Widget::TokenService.new(token: @token).decode_token
                         else
                           {}
                         end
  end

  def set_contact
    return if @auth_token_params[:source_id].nil?

    @contact_inbox = ::ContactInbox.find_by(
      inbox_id: @web_widget.inbox.id,
      source_id: @auth_token_params[:source_id]
    )

    @contact = @contact_inbox&.contact
  end

  def build_contact
    return if @contact.present?

    @contact_inbox, @token = build_contact_inbox_with_token(@web_widget, additional_attributes)
    @contact = @contact_inbox.contact
  end

  def ensure_account_is_active
    render json: { error: 'Account is suspended' }, status: :unauthorized unless @web_widget.inbox.account.active?
  end

  def ensure_location_is_supported; end

  def additional_attributes
    if @web_widget.inbox.account.feature_enabled?('ip_lookup')
      { created_at_ip: request.remote_ip }
    else
      {}
    end
  end

  def permitted_params
    params.permit(:website_token, :cw_conversation, :locale)
  end

  def allow_iframe_requests
    if @web_widget.allowed_domains.blank?
      response.headers.delete('X-Frame-Options')
    else
      domains = @web_widget.allowed_domains.split(',').map(&:strip).join(' ')
      response.headers['Content-Security-Policy'] = "frame-ancestors #{domains}"
    end
  end

  def detect_widget_locale
    # Priority: URL param > Help Center cookie > Browser Accept-Language > Account default
    # Check help center cookie first since users set their preference there
    url_locale = permitted_params[:locale]
    help_center_locale = cookies[:help_center_locale]
    browser_locale = locale_from_browser_for_widget
    account_locale = @web_widget.account.locale

    Rails.logger.info "[Widget] Locale detection - URL: #{url_locale}, HelpCenter: #{help_center_locale}, Browser: #{browser_locale}, Account: #{account_locale}"

    detected_locale = url_locale || help_center_locale || browser_locale || account_locale
    @widget_locale = validate_widget_locale(detected_locale)

    Rails.logger.info "[Widget] Final locale: #{@widget_locale}"
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

WidgetsController.prepend_mod_with('WidgetsController')
