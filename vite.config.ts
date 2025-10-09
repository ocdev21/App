import { defineConfig } from "vite";
import path from "path";

export default defineConfig({
  // Direct JSX handling without plugin - eliminates Docker build issues
  esbuild: {
    jsx: 'automatic',
    jsxImportSource: 'react'
  },
  resolve: {
    alias: {
      "@": path.resolve(import.meta.dirname, "client", "src"),
      "@shared": path.resolve(import.meta.dirname, "shared"),
      "@assets": path.resolve(import.meta.dirname, "attached_assets"),
    },
  },
  root: path.resolve(import.meta.dirname, "client"),
  build: {
    outDir: path.resolve(import.meta.dirname, "dist/public"),
    emptyOutDir: true,
    // Optimize for production deployment
    sourcemap: false, // Disable sourcemaps for production builds
  },
  server: {
    // Environment-driven host/port for flexible deployment
    host: process.env.VITE_HOST || "0.0.0.0", // Allow external connections
    port: Number(process.env.VITE_PORT) || 5173, // Configurable port
    allowedHosts: true, // Allow all hosts for Replit/OpenShift environment
    proxy: {
      "/api": {
        target: "http://127.0.0.1:5000", // Backend server port
        changeOrigin: true,
      },
      "/ws": {
        target: "http://127.0.0.1:5000", // Backend WebSocket server
        ws: true, // Enable WebSocket proxying
        changeOrigin: true,
      },
    },
    fs: {
      strict: true,
      deny: ["**/.*"],
    },
  },
});
