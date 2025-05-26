import { resolve } from 'path';
import { defineConfig } from 'vite';
import tsconfigPaths from 'vite-tsconfig-paths';

const rootDir = resolve(__dirname);
const srcDir = resolve(rootDir, 'src');
const outDir = resolve(rootDir, 'dist');

export default defineConfig({
  resolve: {
    alias: {
      '@': srcDir,
    },
  },
  plugins: [
    tsconfigPaths(),
    // VitePluginNode has compatibility issues with the current Vite version
  ],
  build: {
    outDir,
    emptyOutDir: true,
    sourcemap: true,
    minify: false,
    target: 'node16',

    // Build for ESM
    lib: {
      entry: {
        index: resolve(srcDir, 'index.ts'),
      },
      formats: ['es'],
      fileName: (format, entryName) => `${entryName}.js`,
    },

    rollupOptions: {
      external: [
        // Node.js built-ins
        'async_hooks',
        'buffer',
        'child_process',
        'cluster',
        'console',
        'constants',
        'crypto',
        'dgram',
        'dns',
        'domain',
        'events',
        'fs',
        'http',
        'http2',
        'https',
        'inspector',
        'module',
        'net',
        'os',
        'path',
        'perf_hooks',
        'process',
        'punycode',
        'querystring',
        'readline',
        'repl',
        'stream',
        'string_decoder',
        'timers',
        'tls',
        'trace_events',
        'tty',
        'url',
        'util',
        'v8',
        'vm',
        'wasi',
        'worker_threads',
        'zlib',
        // Node.js namespaced imports
        /^node:.*/,
        
        // Problematic modules that should be kept external
        'iconv',
        'iconv-lite',
        'encoding',
        'encoding-japanese',
        'safer-buffer',
        'buffer-from'
      ],
      output: {
        // Ensure proper interoperability
        format: 'es',
        // Fix for circular dependencies in bundled modules
        manualChunks: undefined,
        // Prevent minification for better debugging
        minifyInternalExports: false
      }
    },
  },
  optimizeDeps: {
    exclude: ['fsevents'],
  },
  server: {
    port: 8765,
    host: 'localhost',
  },
});
