import { defineConfig } from "vite"
import vue from "@vitejs/plugin-vue"

// Must match the dev-server origin that config/initializers/vite.rb and the
// development CSP allow.
const devServerHost = process.env.VITE_DEV_SERVER_HOST ?? "localhost:5173"
const [hostname = "localhost", port = "5173"] = devServerHost.split(":")

// Built assets go to public/vite with a manifest that ViteHelper reads; in
// development ViteHelper points at the dev server instead.
export default defineConfig({
  base: "/vite/",
  publicDir: false,
  // Root-relative URLs in templates (/og_img.png) are files Rails serves from
  // public/, not modules to bundle.
  plugins: [vue({ template: { transformAssetUrls: { includeAbsolute: false } } })],
  build: {
    outDir: "public/vite",
    emptyOutDir: true,
    manifest: true,
    // The single-page application, and the API documentation page (/api/docs).
    rolldownOptions: { input: ["app/frontend/entrypoints/application.ts", "app/frontend/entrypoints/api-docs.ts"] },
  },
  server: {
    host: hostname,
    port: Number(port),
    strictPort: true,
    origin: `http://${devServerHost}`,
    // Open the app on this server: everything outside /vite/ is passed on to
    // Rails, so the page, its API and the icon sprite share one origin (SVG
    // <use> refuses files from another origin).
    proxy: { "^/(?!vite/)": { target: "http://127.0.0.1:3000" } },
  },
})
