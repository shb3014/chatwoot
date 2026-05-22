import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { JSDOM } from 'jsdom';
import {
  InitializationHelpers,
  openExternalLinksInNewTab,
  getHeadingsfromTheArticle,
} from '../portalHelpers';

describe('InitializationHelpers.navigateToLocalePage', () => {
  let dom;
  let document;
  let window;

  beforeEach(() => {
    dom = new JSDOM(
      '<!DOCTYPE html><html><body><div class="locale-switcher" data-portal-slug="test-slug"><select><option value="en">English</option><option value="fr">French</option></select></div></body></html>',
      { url: 'http://localhost/' }
    );
    document = dom.window.document;
    window = dom.window;
    global.document = document;
    global.window = window;
  });

  afterEach(() => {
    dom = null;
    document = null;
    window = null;
    delete global.document;
    delete global.window;
  });

  it('sets up document event listener regardless of locale-switcher existence', () => {
    document.querySelector('.locale-switcher').remove();
    const documentSpy = vi.spyOn(document, 'addEventListener');
    InitializationHelpers.navigateToLocalePage();
    expect(documentSpy).toHaveBeenCalledWith('change', expect.any(Function));
    documentSpy.mockRestore();
  });

  it('adds document-level event listener to handle locale switching', () => {
    const documentSpy = vi.spyOn(document, 'addEventListener');

    InitializationHelpers.navigateToLocalePage();

    expect(documentSpy).toHaveBeenCalledWith('change', expect.any(Function));
    documentSpy.mockRestore();
  });
});

describe('openExternalLinksInNewTab', () => {
  let dom;
  let document;
  let window;

  beforeEach(() => {
    dom = new JSDOM(
      `<!DOCTYPE html>
      <html>
        <body>
          <div id="cw-article-content">
            <a href="https://external.com" id="external">External</a>
            <a href="https://app.chatwoot.com/page" id="internal">Internal</a>
            <a href="https://custom.domain.com/page" id="custom">Custom</a>
            <a href="https://example.com" id="nested"><code>Code</code><strong>Bold</strong></a>
            <ul>
              <li>Visit the preferences centre here &gt; <a href="https://external.com" id="list-link"><strong>https://external.com</strong></a></li>
            </ul>
          </div>
        </body>
      </html>`,
      { url: 'https://app.chatwoot.com/hc/article' }
    );

    document = dom.window.document;
    window = dom.window;

    window.portalConfig = {
      customDomain: 'custom.domain.com',
      hostURL: 'app.chatwoot.com',
    };

    global.document = document;
    global.window = window;
  });

  afterEach(() => {
    dom = null;
    document = null;
    window = null;
    delete global.document;
    delete global.window;
  });

  const simulateClick = selector => {
    const element = document.querySelector(selector);
    const event = new window.MouseEvent('click', { bubbles: true });
    element.dispatchEvent(event);
    return element.closest('a') || element;
  };

  it('opens external links in new tab', () => {
    openExternalLinksInNewTab();

    const link = simulateClick('#external');
    expect(link.target).toBe('_blank');
    expect(link.rel).toBe('noopener noreferrer');
  });

  it('preserves internal links', () => {
    openExternalLinksInNewTab();

    const internal = simulateClick('#internal');
    const custom = simulateClick('#custom');

    expect(internal.target).not.toBe('_blank');
    expect(custom.target).not.toBe('_blank');
  });

  it('handles clicks on nested elements', () => {
    openExternalLinksInNewTab();

    simulateClick('#nested code');
    simulateClick('#nested strong');

    const link = document.getElementById('nested');
    expect(link.target).toBe('_blank');
    expect(link.rel).toBe('noopener noreferrer');
  });

  it('handles links inside list items with strong tags', () => {
    openExternalLinksInNewTab();

    // Click on the strong element inside the link in the list
    simulateClick('#list-link strong');

    const link = document.getElementById('list-link');
    expect(link.target).toBe('_blank');
    expect(link.rel).toBe('noopener noreferrer');
  });

  it('opens external links in a new tab even if customDomain is empty', () => {
    window = dom.window;
    window.portalConfig = {
      hostURL: 'app.chatwoot.com',
    };

    global.window = window;

    openExternalLinksInNewTab();

    const link = simulateClick('#external');
    const internal = simulateClick('#internal');
    const custom = simulateClick('#custom');

    expect(link.target).toBe('_blank');
    expect(link.rel).toBe('noopener noreferrer');

    expect(internal.target).not.toBe('_blank');
    // this will be blank since the configs customDomain is empty
    // which is a fair expectation
    expect(custom.target).toBe('_blank');
  });

  it('opens external links in a new tab even if hostURL is empty', () => {
    window = dom.window;
    window.portalConfig = {
      customDomain: 'custom.domain.com',
    };

    global.window = window;

    openExternalLinksInNewTab();

    const link = simulateClick('#external');
    const internal = simulateClick('#internal');
    const custom = simulateClick('#custom');

    expect(link.target).toBe('_blank');
    expect(link.rel).toBe('noopener noreferrer');

    expect(internal.target).not.toBe('_blank');
    expect(custom.target).not.toBe('_blank');
  });
});

describe('getHeadingsfromTheArticle', () => {
  let dom;

  const setupDom = bodyHtml => {
    dom = new JSDOM(
      `<!DOCTYPE html><html><body><div id="cw-article-content">${bodyHtml}</div></body></html>`,
      { url: 'http://localhost/' }
    );
    global.document = dom.window.document;
    global.window = dom.window;
  };

  afterEach(() => {
    dom = null;
    delete global.document;
    delete global.window;
  });

  it('returns an empty list when the article container is missing', () => {
    dom = new JSDOM('<!DOCTYPE html><html><body></body></html>', {
      url: 'http://localhost/',
    });
    global.document = dom.window.document;
    global.window = dom.window;

    expect(getHeadingsfromTheArticle()).toEqual([]);
  });

  it('preserves CJK characters in heading slugs', () => {
    setupDom('<h1>测试标题</h1><h2>Hello 世界</h2><h3>配置说明</h3>');

    const rows = getHeadingsfromTheArticle();

    expect(rows.map(row => row.slug)).toEqual([
      '测试标题',
      'hello-世界',
      '配置说明',
    ]);
    expect(document.querySelector('h1').id).toBe('测试标题');
    expect(document.querySelector('h2').id).toBe('hello-世界');
    expect(document.querySelector('h3').id).toBe('配置说明');
  });

  it('disambiguates duplicate headings with a counter', () => {
    setupDom('<h3>配置</h3><h3>配置</h3><h3>配置</h3>');

    const rows = getHeadingsfromTheArticle();

    expect(rows.map(row => row.slug)).toEqual(['配置', '配置-2', '配置-3']);
  });

  it('falls back to "section" when the heading has no slug-able characters', () => {
    setupDom('<h2>***</h2><h2>***</h2>');

    const rows = getHeadingsfromTheArticle();

    expect(rows.map(row => row.slug)).toEqual(['section', 'section-2']);
  });
});
