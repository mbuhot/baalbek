import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.alembic.baalbek.dispatch',
  appName: 'Baalbek Dispatch',
  webDir: '../web/dist',
  plugins: {
    // Patches fetch/XMLHttpRequest to issue native requests, which the WebView
    // never applies CORS to. Bundled in @capacitor/core, off by default.
    CapacitorHttp: {
      enabled: true,
    },
  },
};

export default config;
