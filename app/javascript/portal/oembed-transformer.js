/**
 * 将 CKEditor5 的 <oembed> 标签转换为实际的嵌入式播放器
 * 支持 YouTube, Vimeo, Dailymotion, Spotify 等
 */

class OEmbedTransformer {
  constructor() {
    this.providers = [
      {
        // YouTube
        pattern: /^(?:https?:)?\/\/(?:www\.)?(?:youtube\.com|youtu\.be)\/.+/,
        transform: url => {
          const videoId = this.getYouTubeVideoId(url);
          if (!videoId) return null;

          return `<div class="responsive-embed" style="position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden;">
            <iframe
              src="https://www.youtube.com/embed/${videoId}"
              class="responsive-embed__media"
              style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;"
              frameborder="0"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowfullscreen>
            </iframe>
          </div>`;
        },
      },
      {
        // Vimeo
        pattern: /^(?:https?:)?\/\/(?:www\.)?vimeo\.com\/.+/,
        transform: url => {
          const videoId = url.match(/vimeo\.com\/(\d+)/)?.[1];
          if (!videoId) return null;

          return `<div class="responsive-embed" style="position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden;">
            <iframe
              src="https://player.vimeo.com/video/${videoId}"
              class="responsive-embed__media"
              style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;"
              frameborder="0"
              allow="autoplay; fullscreen; picture-in-picture"
              allowfullscreen>
            </iframe>
          </div>`;
        },
      },
      {
        // Dailymotion
        pattern: /^(?:https?:)?\/\/(?:www\.)?dailymotion\.com\/.+/,
        transform: url => {
          const videoId = url.match(/dailymotion\.com\/video\/([^_]+)/)?.[1];
          if (!videoId) return null;

          return `<div class="responsive-embed" style="position: relative; padding-bottom: 56.25%; height: 0; overflow: hidden;">
            <iframe
              src="https://www.dailymotion.com/embed/video/${videoId}"
              class="responsive-embed__media"
              style="position: absolute; top: 0; left: 0; width: 100%; height: 100%;"
              frameborder="0"
              allow="autoplay; fullscreen"
              allowfullscreen>
            </iframe>
          </div>`;
        },
      },
      {
        // Spotify
        pattern: /^(?:https?:)?\/\/(?:open\.)?spotify\.com\/.+/,
        transform: url => {
          const match = url.match(/spotify\.com\/(track|album|playlist)\/([a-zA-Z0-9]+)/);
          if (!match) return null;

          const [, type, id] = match;
          const height = type === 'track' ? '80' : '380';

          return `<iframe
            src="https://open.spotify.com/embed/${type}/${id}"
            width="100%"
            height="${height}"
            frameborder="0"
            allowtransparency="true"
            allow="encrypted-media">
          </iframe>`;
        },
      },
      {
        // Twitter
        pattern: /^(?:https?:)?\/\/(?:www\.)?(?:twitter\.com|x\.com)\/.+\/status\/.+/,
        transform: url => {
          // Twitter 需要使用它们的 widget.js，这里返回一个链接
          return `<blockquote class="twitter-tweet">
            <a href="${url}">${url}</a>
          </blockquote>
          <script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>`;
        },
      },
    ];
  }

  getYouTubeVideoId(url) {
    // 支持多种 YouTube URL 格式
    const patterns = [
      /(?:youtube\.com\/watch\?v=|youtu\.be\/)([^&\n?#]+)/,
      /youtube\.com\/embed\/([^&\n?#]+)/,
      /youtube\.com\/v\/([^&\n?#]+)/,
    ];

    for (const pattern of patterns) {
      const match = url.match(pattern);
      if (match) return match[1];
    }

    return null;
  }

  transformOEmbeds(container = document) {
    const oembeds = container.querySelectorAll('oembed');

    oembeds.forEach(oembed => {
      const url = oembed.getAttribute('url');
      if (!url) return;

      // 查找匹配的提供商
      const provider = this.providers.find(p => p.pattern.test(url));

      if (provider) {
        const html = provider.transform(url);
        if (html) {
          // 创建一个包装 div
          const wrapper = document.createElement('div');
          wrapper.className = 'oembed-wrapper';
          wrapper.innerHTML = html;

          // 替换 oembed 标签
          oembed.parentNode.replaceChild(wrapper, oembed);
        }
      } else {
        // 不支持的媒体类型，显示链接
        const link = document.createElement('a');
        link.href = url;
        link.textContent = url;
        link.target = '_blank';
        link.rel = 'noopener noreferrer';
        oembed.parentNode.replaceChild(link, oembed);
      }
    });
  }

  init() {
    // 立即转换页面上的 oembed
    this.transformOEmbeds();
  }
}

// 导出单例
export const oembedTransformer = new OEmbedTransformer();

