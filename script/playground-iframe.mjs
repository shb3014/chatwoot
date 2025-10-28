import { createServer } from 'vite';

// 强制 TEST 模式，vite.config.ts 将只启用所需最小插件
process.env.TEST = 'true';

const server = await createServer({
  server: {
    open: '/playground/iframe-helper/',
  },
  // 覆盖 PostCSS 配置，避免读取根目录 postcss.config.js
  css: {
    postcss: {
      plugins: [],
    },
  },
});

await server.listen();
server.printUrls();



