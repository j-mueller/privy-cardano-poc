import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { PrivyProvider } from "@privy-io/react-auth";
import { Buffer } from "buffer";
import "./index.css";
import App from "./App.tsx";

const runtimePrivyAppId =
  import.meta.env.VITE_PRIVY_APP_ID ?? "__VITE_PRIVY_APP_ID__";
const runtimePrivyClientId =
  import.meta.env.VITE_PRIVY_CLIENT_ID ?? "__VITE_PRIVY_CLIENT_ID__";

const globalScope = globalThis as typeof globalThis & {
  Buffer?: typeof Buffer;
  buffer?: { Buffer: typeof Buffer };
};

if (!globalScope.Buffer) {
  globalScope.Buffer = Buffer;
}

if (!globalScope.buffer) {
  globalScope.buffer = { Buffer };
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <PrivyProvider
      appId={runtimePrivyAppId}
      clientId={runtimePrivyClientId}
      config={{
        embeddedWallets: {
          ethereum: {
            createOnLogin: "off",
          },
        },
      }}
    >
      <App />
    </PrivyProvider>
  </StrictMode>
);
