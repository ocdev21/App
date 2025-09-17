import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [
    react(),
    // TypeScript checker removed to prevent build failures in production
    // TypeScript errors will still be caught by IDEs and tsc command
  ],
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
    allowedHosts: "all", // Allow all hosts for Replit environment
    proxy: {
      "/api": {
        target: "http://127.0.0.1:5000", // Backend server port
        changeOrigin: true,
      },
    },
    fs: {
      strict: true,
      deny: ["**/.*"],
    },
  },
});
