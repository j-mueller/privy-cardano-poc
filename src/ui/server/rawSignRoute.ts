import { PrivyClient } from "@privy-io/node";
import type { IncomingMessage, ServerResponse } from "node:http";

type RawSignHashFunction = "sha256" | "blake2b256" | "keccak256";

type RawSignRequestBody = {
  walletId?: string;
  transactionHex?: string;
  authorizationSignature?: string;
  hashFunction?: RawSignHashFunction;
};

type MiddlewareNext = () => void;

const API_PATH = "/api/raw-sign";
const ALLOWED_HASH_FUNCTIONS = new Set<RawSignHashFunction>([
  "sha256",
  "blake2b256",
  "keccak256",
]);

let privyClient: PrivyClient | null = null;

function getEnv(name: "VITE_PRIVY_APP_ID" | "PRIVY_APP_SECRET"): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function getPrivyClient(): PrivyClient {
  if (!privyClient) {
    privyClient = new PrivyClient({
      appId: getEnv("VITE_PRIVY_APP_ID"),
      appSecret: getEnv("PRIVY_APP_SECRET"),
    });
  }

  return privyClient;
}

function sendJson(
  response: ServerResponse,
  statusCode: number,
  payload: Record<string, string>
) {
  response.statusCode = statusCode;
  response.setHeader("Content-Type", "application/json");
  response.end(JSON.stringify(payload));
}

async function readJsonBody(request: IncomingMessage): Promise<RawSignRequestBody> {
  let body = "";

  for await (const chunk of request) {
    body += typeof chunk === "string" ? chunk : chunk.toString("utf8");
  }

  if (!body) {
    return {};
  }

  return JSON.parse(body) as RawSignRequestBody;
}

function normalizeHex(hex: string): string {
  const trimmed = hex.trim();
  const normalized = trimmed.startsWith("0x") ? trimmed.slice(2) : trimmed;

  if (normalized.length === 0) {
    throw new Error("Transaction hex cannot be empty.");
  }

  if (normalized.length % 2 !== 0) {
    throw new Error("Transaction hex must contain an even number of characters.");
  }

  if (!/^[0-9a-fA-F]+$/.test(normalized)) {
    throw new Error("Transaction hex contains non-hex characters.");
  }

  return normalized.toLowerCase();
}

function getErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message) {
    return error.message;
  }

  return "raw_sign failed.";
}

export function createRawSignMiddleware() {
  return async (
    request: IncomingMessage,
    response: ServerResponse,
    next: MiddlewareNext
  ) => {
    const requestUrl = request.url?.split("?")[0];

    if (requestUrl !== API_PATH) {
      next();
      return;
    }

    if (request.method !== "POST") {
      sendJson(response, 405, { error: "Method not allowed." });
      return;
    }

    try {
      const {
        walletId,
        transactionHex,
        authorizationSignature,
        hashFunction = "blake2b256",
      } =
        await readJsonBody(request);

      if (!walletId) {
        sendJson(response, 400, { error: "Missing wallet ID." });
        return;
      }

      if (!transactionHex) {
        sendJson(response, 400, { error: "Missing transaction hex." });
        return;
      }

      if (!authorizationSignature) {
        sendJson(response, 400, { error: "Missing authorization signature." });
        return;
      }

      if (!ALLOWED_HASH_FUNCTIONS.has(hashFunction)) {
        sendJson(response, 400, { error: "Unsupported hash function." });
        return;
      }

      const normalizedHex = normalizeHex(transactionHex);
      const privy = getPrivyClient();
      const rawSignResult = await privy.wallets()._rawSign(walletId, {
        "privy-authorization-signature": authorizationSignature,
        params: {
          bytes: Buffer.from(normalizedHex, "hex").toString("base64"),
          encoding: "base64",
          hash_function: hashFunction,
        },
      });

      sendJson(response, 200, {
        signature: rawSignResult.data.signature,
      });
    } catch (error) {
      sendJson(response, 500, { error: getErrorMessage(error) });
    }
  };
}
