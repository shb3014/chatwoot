class Api::V1::Accounts::Captain::TranslationsController < Api::V1::Accounts::BaseController
  def create
    content = params[:content]
    target_language = params[:target_language]

    return render_could_not_create_error('Content is required') if content.blank?
    return render_could_not_create_error('Target language is required') if target_language.blank?

    service = Llm::TranslationService.new
    translation = service.translate_message(content, target_language: target_language)

    render json: { translation: translation }
  end
end
