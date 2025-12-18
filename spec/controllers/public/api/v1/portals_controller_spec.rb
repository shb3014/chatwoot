require 'rails_helper'

RSpec.describe Public::Api::V1::PortalsController, type: :request do
  let!(:account) { create(:account) }
  let!(:agent) { create(:user, account: account, role: :agent) }
  let!(:portal) { create(:portal, slug: 'test-portal', account_id: account.id, custom_domain: 'www.example.com') }

  before do
    create(:portal, slug: 'test-portal-1', account_id: account.id)
    create(:portal, slug: 'test-portal-2', account_id: account.id)
    create_list(:article, 3, account: account, author: agent, portal: portal, status: :published)
    create_list(:article, 2, account: account, author: agent, portal: portal, status: :draft)
  end

  describe 'GET /public/api/v1/portals/{portal_slug}' do
    it 'Show portal and categories belonging to the portal' do
      get "/hc/#{portal.slug}/en"

      expect(response).to have_http_status(:success)
    end

    it 'Throws unauthorised error for unknown domain' do
      portal.update(custom_domain: 'www.something.com')

      get "/hc/#{portal.slug}/en"

      expect(response).to have_http_status(:unauthorized)
      json_response = response.parsed_body

      expect(json_response['error']).to eql "Domain: www.example.com is not registered with us. \
      Please send us an email at support@chatwoot.com with the custom domain name and account API key"
    end

    context 'when portal has a logo' do
      it 'includes the logo as favicon' do
        # Attach a test image to the portal
        file = Rails.root.join('spec/assets/sample.png').open
        portal.logo.attach(io: file, filename: 'sample.png', content_type: 'image/png')
        file.close

        get "/hc/#{portal.slug}/en"

        expect(response).to have_http_status(:success)
        expect(response.body).to include('<link rel="icon" href=')
      end
    end

    context 'when portal has no logo' do
      it 'does not include a favicon link' do
        # Ensure logo is not attached
        portal.logo.purge if portal.logo.attached?

        get "/hc/#{portal.slug}/en"

        expect(response).to have_http_status(:success)
        expect(response.body).not_to include('<link rel="icon" href=')
      end
    end
  end

  describe 'GET /public/api/v1/portals/{portal_slug}/sitemap' do
    context 'when custom_domain is present' do
      it 'gets a valid sitemap' do
        get "/hc/#{portal.slug}/sitemap.xml"
        expect(response).to have_http_status(:success)
        expect(response.body).to match(/<sitemap/)
        expect(Nokogiri::XML(response.body).errors).to be_empty
      end

      it 'has valid sitemap links' do
        get "/hc/#{portal.slug}/sitemap.xml"
        expect(response).to have_http_status(:success)
        parsed_xml = Nokogiri::XML(response.body)
        links = parsed_xml.css('loc')

        links.each do |link|
          expect(link.text).to match(%r{https://www\.example\.com/hc/test-portal/articles/\d+})
        end

        expect(links.length).to eq 3
      end
    end
  end

  describe 'Automatic locale detection and redirection' do
    let!(:portal_with_locales) do
      create(:portal, slug: 'multi-lang-portal', account_id: account.id,
                      config: { 'allowed_locales' => %w[en zh es], 'default_locale' => 'en' })
    end

    context 'when visiting without locale parameter' do
      it 'redirects to default locale when no Accept-Language header is present' do
        get "/hc/#{portal_with_locales.slug}"
        expect(response).to redirect_to("/hc/#{portal_with_locales.slug}/en")
      end

      it 'redirects to browser locale when Accept-Language header matches supported locale' do
        get "/hc/#{portal_with_locales.slug}", headers: { 'HTTP_ACCEPT_LANGUAGE' => 'zh-CN,zh;q=0.9,en;q=0.8' }
        expect(response).to redirect_to("/hc/#{portal_with_locales.slug}/zh")
      end

      it 'redirects to base locale when Accept-Language includes variant' do
        get "/hc/#{portal_with_locales.slug}", headers: { 'HTTP_ACCEPT_LANGUAGE' => 'es-MX,es;q=0.9' }
        expect(response).to redirect_to("/hc/#{portal_with_locales.slug}/es")
      end

      it 'redirects to best matching locale based on quality values' do
        get "/hc/#{portal_with_locales.slug}", headers: { 'HTTP_ACCEPT_LANGUAGE' => 'fr;q=0.9,zh;q=0.8,en;q=0.7' }
        # French not supported, should pick Chinese (higher quality than English)
        expect(response).to redirect_to("/hc/#{portal_with_locales.slug}/zh")
      end

      it 'redirects to default locale when Accept-Language has no supported locales' do
        get "/hc/#{portal_with_locales.slug}", headers: { 'HTTP_ACCEPT_LANGUAGE' => 'fr-FR,de-DE' }
        expect(response).to redirect_to("/hc/#{portal_with_locales.slug}/en")
      end

      it 'uses cookie locale over browser detection when cookie is set' do
        cookies[:help_center_locale] = 'es'
        get "/hc/#{portal_with_locales.slug}", headers: { 'HTTP_ACCEPT_LANGUAGE' => 'zh-CN' }
        expect(response).to redirect_to("/hc/#{portal_with_locales.slug}/es")
      end
    end

    context 'when using custom domain' do
      let!(:custom_portal) do
        create(:portal, slug: 'custom-portal', account_id: account.id,
                        custom_domain: 'help.example.com',
                        config: { 'allowed_locales' => %w[en zh], 'default_locale' => 'en' })
      end

      it 'redirects to detected locale for custom domain' do
        get 'http://help.example.com/',
            headers: { 'HTTP_ACCEPT_LANGUAGE' => 'zh-CN,zh;q=0.9', 'Host' => 'help.example.com' }
        expect(response).to redirect_to('/zh')
      end

      it 'redirects to default locale for custom domain when no matching locale' do
        get 'http://help.example.com/',
            headers: { 'HTTP_ACCEPT_LANGUAGE' => 'fr-FR', 'Host' => 'help.example.com' }
        expect(response).to redirect_to('/en')
      end
    end

    context 'when locale parameter is present' do
      it 'does not redirect and uses the provided locale' do
        get "/hc/#{portal_with_locales.slug}/es", headers: { 'HTTP_ACCEPT_LANGUAGE' => 'zh-CN' }
        expect(response).to have_http_status(:success)
        expect(response).not_to be_redirect
      end
    end
  end
end
