import { defineConfig } from "vite";
import path from "path";
export default defineConfig({
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
        sourcemap: false,
    },
    server: {
        host: process.env.VITE_HOST || "0.0.0.0",
        port: Number(process.env.VITE_PORT) || 5173,
        allowedHosts: true,
        proxy: {
            "/api": {
                target: "http://127.0.0.1:5000",
                changeOrigin: true,
            },
            "/ws": {
                target: "http://127.0.0.1:5000",
                ws: true,
                changeOrigin: true,
            },
        },
        fs: {
            strict: true,
            deny: ["**/.*"],
        },
    },
});
//# sourceMappingURL=vite.config.js.map