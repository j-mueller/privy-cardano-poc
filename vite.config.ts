import { defineConfig, loadEnv, type Plugin } from "vite";
import path from "node:path";
import react from "@vitejs/plugin-react";
import { nodePolyfills } from "vite-plugin-node-polyfills";
import tailwindcss from "@tailwindcss/vite";
import { createRawSignMiddleware } from "./server/rawSignRoute";

function privyRawSignPlugin(): Plugin {
  const middleware = createRawSignMiddleware();

  return {
    name: "privy-raw-sign-plugin",
    configureServer(server) {
      server.middlewares.use(middleware);
    },
    configurePreviewServer(server) {
      server.middlewares.use(middleware);
    },
  };
}

export default defineConfig(({ mode }) => {
  // Vite exposes env vars to the browser via import.meta.env, but our local
  // raw-sign middleware runs on the Node side and reads process.env.
  Object.assign(process.env, loadEnv(mode, process.cwd(), ""));

  return {
    plugins: [react(), tailwindcss(), nodePolyfills(), privyRawSignPlugin()],
    resolve: {
      alias: {
        "@": path.resolve(__dirname, "./src"),
      },
    },
    build: {
      outDir: "build",
    },
  };
});
