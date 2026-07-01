class ChatwootMarkdownRenderer
  # Node types that contain code/HTML and should be excluded from the
  # plain-text preview (e.g. category article snippets). Keeping these in
  # would leak raw CSS/HTML/JS into the visible preview text.
  STRIPPED_PREVIEW_NODE_TYPES = %i[code_block html_block code html_inline].freeze

  def initialize(content)
    @content = content
  end

  def render_message
    markdown_renderer = BaseMarkdownRenderer.new
    doc = CommonMarker.render_doc(@content, :DEFAULT)
    html = markdown_renderer.render(doc)
    render_as_html_safe(html)
  end

  def render_article
    markdown_renderer = CustomMarkdownRenderer.new
    doc = CommonMarker.render_doc(@content, :DEFAULT, [:table])
    html = markdown_renderer.render(doc)

    render_as_html_safe(html)
  end

  def render_markdown_to_plain_text
    doc = CommonMarker.render_doc(@content.to_s, :DEFAULT)
    strip_preview_unfriendly_nodes(doc)
    doc.to_plaintext.squish
  end

  private

  def strip_preview_unfriendly_nodes(doc)
    nodes_to_delete = []
    doc.walk do |node|
      nodes_to_delete << node if STRIPPED_PREVIEW_NODE_TYPES.include?(node.type)
    end
    nodes_to_delete.each(&:delete)
  end

  def render_as_html_safe(html)
    # rubocop:disable Rails/OutputSafety
    html.html_safe
    # rubocop:enable Rails/OutputSafety
  end
end
