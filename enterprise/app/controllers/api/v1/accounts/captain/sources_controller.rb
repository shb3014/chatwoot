class Api::V1::Accounts::Captain::SourcesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  before_action :set_current_page, only: [:index]
  before_action :set_sources, except: [:create]
  before_action :set_source, only: [:show, :update, :destroy, :recrawl]
  RESULTS_PER_PAGE = 25

  def index
    base_query = @sources
    base_query = base_query.by_type(permitted_params[:source_type]) if permitted_params[:source_type].present?
    base_query = base_query.where('title ILIKE ?', "%#{permitted_params[:search]}%") if permitted_params[:search].present?

    @sources_count = base_query.count
    @sources = base_query.page(@current_page).per(RESULTS_PER_PAGE)
  end

  def show; end

  def create
    @source = Current.account.captain_sources.build(source_params)
    @source.save!
  rescue ActiveRecord::RecordInvalid => e
    render_could_not_create_error(e.record.errors.full_messages.join(', '))
  end

  def update
    @source.update!(source_update_params)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  def recrawl
    if @source.private_article?
      render json: { error: 'Cannot recrawl a private article' }, status: :unprocessable_entity
      return
    end

    @source.recrawl!
  end

  def destroy
    @source.destroy!
    head :no_content
  end

  private

  def set_sources
    @sources = Current.account.captain_sources.ordered
  end

  def set_source
    @source = @sources.find(permitted_params[:id])
  end

  def set_current_page
    @current_page = permitted_params[:page] || 1
  end

  def permitted_params
    params.permit(:source_type, :search, :page, :id, :account_id)
  end

  def source_params
    params.require(:source).permit(:title, :source_type, :external_link, :content, :pdf_file)
  end

  def source_update_params
    params.require(:source).permit(:title, :content)
  end
end
