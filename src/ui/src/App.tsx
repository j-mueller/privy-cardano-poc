import { useEffect, useMemo, useState } from "react";
import {
  useAuthorizationSignature,
  usePrivy,
  useUser,
  type LinkedAccountWithMetadata,
} from "@privy-io/react-auth";
import { useCreateWallet as useCreateExtendedWallet } from "@privy-io/react-auth/extended-chains";
import {
  Check,
  Copy,
  LoaderCircle,
  LogOut,
  ShieldCheck,
  Sparkles,
  WalletCards,
} from "lucide-react";

import { Alert, AlertDescription, AlertTitle } from "@/components/ui/alert";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Textarea } from "@/components/ui/textarea";
import {
  getApiV1WalletByPublicKey,
  getApiV1WalletByPublicKeySendFundsByRecipient,
} from "@/generated/client";

type EligibleWallet = {
  id: string;
  address: string;
  chainType: string;
  publicKey?: string;
};

type RawSignResponse = {
  signature?: string;
  error?: string;
};

type RequestPhase = "idle" | "generating" | "signing";

const cardanoServerUrl = import.meta.env.VITE_PRIVY_CARDANO_SERVER_URL?.replace(
  /\/$/,
  ""
);

function cardanoApiFetch(
  input: RequestInfo | URL,
  init?: RequestInit
): Promise<Response> {
  if (!cardanoServerUrl) {
    throw new Error("Missing VITE_PRIVY_CARDANO_SERVER_URL.");
  }

  if (typeof input === "string") {
    return fetch(`${cardanoServerUrl}${input}`, init);
  }

  return fetch(input, init);
}

function getEligibleWallets(
  linkedAccounts: LinkedAccountWithMetadata[] | undefined
): EligibleWallet[] {
  if (!linkedAccounts) {
    return [];
  }

  return linkedAccounts.flatMap((account) => {
    if (
      account.type !== "wallet" ||
      account.chainType !== "sui" ||
      (account.walletClientType !== "privy" &&
        account.walletClientType !== "privy-v2") ||
      typeof account.id !== "string" ||
      account.id.length === 0
    ) {
      return [];
    }

    return [
      {
        id: account.id,
        address: account.address,
        chainType: account.chainType,
        publicKey: account.publicKey,
      },
    ];
  });
}

function isHexString(value: string): boolean {
  return /^(?:0x)?[0-9a-fA-F]+$/.test(value);
}

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join(
    ""
  );
}

function normalizeHexPayload(value: string): string {
  const trimmed = value.trim();
  const normalized = trimmed.startsWith("0x") ? trimmed.slice(2) : trimmed;

  if (!normalized) {
    throw new Error("Payload hex cannot be empty.");
  }

  if (normalized.length % 2 !== 0) {
    throw new Error("Payload hex must contain an even number of characters.");
  }

  if (!/^[0-9a-fA-F]+$/.test(normalized)) {
    throw new Error("Payload hex contains non-hex characters.");
  }

  return normalized.toLowerCase();
}

function hexToBase64(value: string): string {
  const normalized = normalizeHexPayload(value);
  const bytes = normalized.match(/.{1,2}/g);

  if (!bytes) {
    throw new Error("Payload hex cannot be empty.");
  }

  return btoa(
    bytes
      .map((byte) => String.fromCharCode(Number.parseInt(byte, 16)))
      .join("")
  );
}

function normalizePublicKeyToHex(publicKey: string | undefined): string {
  if (!publicKey) {
    return "";
  }

  const trimmed = publicKey.trim();
  if (!trimmed) {
    return "";
  }

  if (isHexString(trimmed)) {
    return `0x${trimmed.replace(/^0x/i, "").toLowerCase()}`;
  }

  try {
    const binary = atob(trimmed);
    const bytes = Uint8Array.from(binary, (char) => char.charCodeAt(0));
    return `0x${bytesToHex(bytes)}`;
  } catch {
    return trimmed;
  }
}

function normalizePublicKeyForCardanoApi(publicKeyHex: string): string {
  const normalized = publicKeyHex.replace(/^0x/i, "");

  if (normalized.length === 66 && normalized.startsWith("00")) {
    return normalized.slice(2);
  }

  return normalized;
}

function formatWalletBalance(balance: WalletInfo["balance"] | undefined): string {
  if (!balance || balance.length === 0) {
    return "No balance found for this wallet.";
  }

  return balance
    .map(([assetId, quantity]) => {
      if (assetId === "lovelace") {
        return `${(quantity / 1_000_000).toLocaleString(undefined, {
          minimumFractionDigits: 0,
          maximumFractionDigits: 6,
        })} Ada`;
      }

      return `${quantity.toLocaleString()} ${assetId}`;
    })
    .join(" • ");
}

function getRequestErrorMessage(error: unknown, fallback: string): string {
  if (
    error &&
    typeof error === "object" &&
    "text" in error &&
    typeof error.text === "string" &&
    error.text.length > 0
  ) {
    return error.text;
  }

  if (error instanceof Error && error.message) {
    return error.message;
  }

  return fallback;
}

function App() {
  const { ready, authenticated, login, logout, user } = usePrivy();
  const { refreshUser } = useUser();
  const { generateAuthorizationSignature } = useAuthorizationSignature();
  const { createWallet } = useCreateExtendedWallet();
  const [receiverAddress, setReceiverAddress] = useState("");
  const [lovelaceAmount, setLovelaceAmount] = useState("");
  const [generatedTransaction, setGeneratedTransaction] =
    useState<ApiTxDummy | null>(null);
  const [signature, setSignature] = useState("");
  const [selectedWalletId, setSelectedWalletId] = useState("");
  const [error, setError] = useState("");
  const [requestPhase, setRequestPhase] = useState<RequestPhase>("idle");
  const [isProvisioningWallet, setIsProvisioningWallet] = useState(false);
  const [hasCopiedPublicKey, setHasCopiedPublicKey] = useState(false);
  const [walletInfo, setWalletInfo] = useState<WalletInfo | null>(null);
  const [walletInfoError, setWalletInfoError] = useState("");
  const [isWalletInfoLoading, setIsWalletInfoLoading] = useState(false);
  const [walletInfoRefreshKey, setWalletInfoRefreshKey] = useState(0);

  const eligibleWallets = useMemo(
    () => getEligibleWallets(user?.linkedAccounts),
    [user?.linkedAccounts]
  );
  useEffect(() => {
    if (
      eligibleWallets.length > 0 &&
      !eligibleWallets.some((wallet) => wallet.id === selectedWalletId)
    ) {
      setSelectedWalletId(eligibleWallets[0].id);
    }
  }, [eligibleWallets, selectedWalletId]);

  const selectedWallet =
    eligibleWallets.find((wallet) => wallet.id === selectedWalletId) ?? null;
  const selectedWalletPublicKeyHex = normalizePublicKeyToHex(
    selectedWallet?.publicKey
  );
  const selectedWalletPublicKeyHash =
    normalizePublicKeyForCardanoApi(selectedWalletPublicKeyHex);
  const isSubmittingRequest = requestPhase !== "idle";

  useEffect(() => {
    let isCancelled = false;

    if (!selectedWalletPublicKeyHash) {
      setWalletInfo(null);
      setWalletInfoError("");
      setIsWalletInfoLoading(false);
      return () => {
        isCancelled = true;
      };
    }

    setIsWalletInfoLoading(true);
    setWalletInfoError("");

    void getApiV1WalletByPublicKey(selectedWalletPublicKeyHash, cardanoApiFetch)
      .then((nextWalletInfo) => {
        if (isCancelled) {
          return;
        }

        setWalletInfo(nextWalletInfo);
      })
      .catch((requestError: unknown) => {
        if (isCancelled) {
          return;
        }

        setWalletInfo(null);
        setWalletInfoError(
          requestError &&
            typeof requestError === "object" &&
            "text" in requestError &&
            typeof requestError.text === "string" &&
            requestError.text.length > 0
            ? requestError.text
            : requestError instanceof Error
              ? requestError.message
              : "Failed to load Cardano wallet info."
        );
      })
      .finally(() => {
        if (isCancelled) {
          return;
        }

        setIsWalletInfoLoading(false);
      });

    return () => {
      isCancelled = true;
    };
  }, [selectedWalletPublicKeyHash, walletInfoRefreshKey]);

  const handleProvisionWallet = async () => {
    setError("");
    setIsProvisioningWallet(true);

    try {
      await createWallet({
        chainType: "sui",
      });
      await refreshUser();
    } catch (provisionError) {
      const message =
        provisionError instanceof Error
          ? provisionError.message
          : "Failed to provision a delegated wallet.";
      setError(message);
    } finally {
      setIsProvisioningWallet(false);
    }
  };

  const handleGenerateTransaction = async () => {
    setError("");
    setSignature("");
    setGeneratedTransaction(null);

    if (!selectedWalletId) {
      setError("No delegated embedded wallet is available for raw_sign.");
      return;
    }

    if (!selectedWalletPublicKeyHash) {
      setError("The selected wallet is missing a Cardano public key.");
      return;
    }

    if (!receiverAddress.trim()) {
      setError("Enter a receiver address.");
      return;
    }

    if (!lovelaceAmount.trim()) {
      setError("Enter an amount in lovelace.");
      return;
    }

    const parsedAmount = Number(lovelaceAmount.trim());
    if (
      !Number.isInteger(parsedAmount) ||
      parsedAmount <= 0 ||
      !Number.isSafeInteger(parsedAmount)
    ) {
      setError("Amount must be a positive whole number of lovelace.");
      return;
    }

    setRequestPhase("generating");

    try {
      const apiTx = await getApiV1WalletByPublicKeySendFundsByRecipient(
        selectedWalletPublicKeyHash,
        receiverAddress.trim(),
        [parsedAmount],
        cardanoApiFetch
      );

      setGeneratedTransaction(apiTx);
      setRequestPhase("signing");

      const payloadBase64 = hexToBase64(apiTx.tx_body_hash);
      const authorizationSignature = await generateAuthorizationSignature({
        version: 1,
        method: "POST",
        url: `https://api.privy.io/v1/wallets/${selectedWalletId}/raw_sign`,
        body: {
          params: {
            bytes: payloadBase64,
            encoding: "base64",
            hash_function: "blake2b256",
          },
        },
        headers: {
          "privy-app-id": import.meta.env.VITE_PRIVY_APP_ID,
        },
      });

      const response = await fetch("/api/raw-sign", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          walletId: selectedWalletId,
          payloadHex: apiTx.tx_body_hash,
          authorizationSignature: authorizationSignature.signature,
        }),
      });

      const data = (await response.json()) as RawSignResponse;

      if (!response.ok || !data.signature) {
        throw new Error(data.error ?? "raw_sign failed.");
      }

      setSignature(data.signature);
    } catch (requestError) {
      setError(
        getRequestErrorMessage(
          requestError,
          "Failed to generate and sign the transaction."
        )
      );
    } finally {
      setRequestPhase("idle");
    }
  };

  const handleCopyPublicKey = async () => {
    if (!selectedWalletPublicKeyHex) {
      return;
    }

    await navigator.clipboard.writeText(selectedWalletPublicKeyHex);
    setHasCopiedPublicKey(true);
    window.setTimeout(() => setHasCopiedPublicKey(false), 1500);
  };

  if (!ready) {
    return (
      <main className="min-h-screen bg-[radial-gradient(circle_at_top,#fff8eb_0%,#f3efe6_48%,#ebe4d7_100%)] px-6 py-10 text-[#1b1813]">
        <div className="mx-auto flex min-h-screen max-w-5xl items-center justify-center">
          <Card className="w-full max-w-xl border-black/5 bg-[#fffdf8]/95">
            <CardHeader className="items-center text-center">
              <Badge variant="secondary" className="w-fit">
                Session
              </Badge>
              <CardTitle>Loading Privy</CardTitle>
              <CardDescription>
                Preparing the embedded wallet session and auth state.
              </CardDescription>
            </CardHeader>
            <CardContent className="flex justify-center pt-0">
              <LoaderCircle className="size-6 animate-spin text-muted-foreground" />
            </CardContent>
          </Card>
        </div>
      </main>
    );
  }

  if (!authenticated) {
    return (
      <main className="min-h-screen bg-[radial-gradient(circle_at_top,#fff8eb_0%,#f3efe6_48%,#ebe4d7_100%)] px-6 py-10 text-[#1b1813]">
        <div className="mx-auto flex min-h-screen max-w-5xl flex-col justify-center py-8">
          <Card className="max-w-3xl overflow-hidden border-black/5 bg-[linear-gradient(145deg,rgba(255,253,248,0.98),rgba(250,244,232,0.94))]">
            <CardHeader className="gap-4">
              <Badge variant="secondary" className="w-fit">
                Privy Cardano Demo
              </Badge>
              <CardTitle className="max-w-2xl text-4xl sm:text-6xl">
                Log in, generate a Cardano transaction, and sign its hash remotely.
              </CardTitle>
              <CardDescription className="max-w-2xl text-base sm:text-lg">
                This screen builds a Cardano transaction through the wallet API,
                then sends the returned tx body hash through Privy&apos;s
                <code className="mx-1 rounded-md bg-black/5 px-1.5 py-0.5 text-sm">
                  raw_sign
                </code>
                endpoint and returns the signature.
              </CardDescription>
            </CardHeader>
            <CardContent className="flex flex-col gap-4 pt-0 sm:flex-row sm:items-center sm:justify-between">
              <Alert className="border-black/5 bg-white/70 sm:max-w-md">
                <ShieldCheck className="mb-3 size-4 text-muted-foreground" />
                <AlertTitle>Remote signing with a Sui embedded wallet</AlertTitle>
                <AlertDescription>
                  The API route signs the returned tx body hash with hashing fixed to
                  <code className="mx-1 rounded-md bg-black/5 px-1.5 py-0.5 text-xs">
                    blake2b256
                  </code>
                  in this demo.
                </AlertDescription>
              </Alert>
              <Button
                size="lg"
                className="w-full sm:w-auto"
              onClick={() => {
                setError("");
                login();
              }}
            >
                <Sparkles />
              Log In With Privy
              </Button>
            </CardContent>
          </Card>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[radial-gradient(circle_at_top,#fff8eb_0%,#f3efe6_48%,#ebe4d7_100%)] px-6 py-10 text-[#1b1813]">
      <div className="mx-auto max-w-5xl">
        <div className="flex flex-col gap-6 lg:flex-row lg:items-start lg:justify-between">
          <div className="max-w-3xl">
            <div className="flex flex-wrap items-center gap-3">
              <Badge variant="secondary">Privy Cardano Demo</Badge>
              <Badge variant={eligibleWallets.length > 0 ? "default" : "outline"}>
                {eligibleWallets.length > 0 ? "Wallet Ready" : "Wallet Needed"}
              </Badge>
            </div>
            <h1 className="mt-4 text-3xl leading-tight font-abc-favorit sm:text-5xl">
              Privy on Cardano
            </h1>
            <p className="mt-4 max-w-3xl text-sm leading-7 text-muted-foreground sm:text-base">
              Use{" "}
              <a
                href="https://privy.io"
                target="_blank"
                rel="noreferrer"
                className="underline underline-offset-4"
              >
                Privy
              </a>{" "}
              to manage your funds on Cardano.
            </p>
          </div>
          <Button variant="outline" onClick={() => logout()}>
            Log Out
            <LogOut />
          </Button>
        </div>

        <div className="mt-10 grid gap-6">
          <Card className="border-black/5 bg-[#fffdf8]/95">
            <CardHeader>
              <div className="flex flex-wrap items-center justify-between gap-3">
                <div>
                  <CardTitle>Transaction request</CardTitle>
                  <CardDescription>
                    Choose a wallet, enter a receiver and lovelace amount, then
                    generate a transaction and sign its tx body hash.
                  </CardDescription>
                </div>
                <Badge variant="outline">Build + Sign</Badge>
              </div>
            </CardHeader>
            <CardContent className="grid gap-6">
              <div className="grid gap-3">
                <label
                  htmlFor="wallet-id"
                  className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground"
                >
                  Delegated wallet
                </label>
                {eligibleWallets.length > 0 ? (
                  <Select value={selectedWalletId} onValueChange={setSelectedWalletId}>
                    <SelectTrigger id="wallet-id">
                      <SelectValue placeholder="Choose a Sui delegated wallet" />
                    </SelectTrigger>
                    <SelectContent>
                      {eligibleWallets.map((wallet) => (
                        <SelectItem key={wallet.id} value={wallet.id}>
                          {wallet.chainType.toUpperCase()} • {wallet.address}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                ) : (
                  <Alert variant="destructive">
                    <AlertTitle>No eligible Sui wallet found</AlertTitle>
                    <AlertDescription>
                      This demo can only call
                      <code className="mx-1 rounded-md bg-black/5 px-1.5 py-0.5 text-xs text-foreground">
                        raw_sign
                      </code>
                      for supported non-Ethereum wallets that already have a
                      Privy wallet ID.
                    </AlertDescription>
                  </Alert>
                )}
                {eligibleWallets.length === 0 ? (
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                    <Button
                      variant="outline"
                      disabled={isProvisioningWallet}
                      onClick={handleProvisionWallet}
                    >
                      {isProvisioningWallet ? (
                        <LoaderCircle className="animate-spin" />
                      ) : (
                        <WalletCards />
                      )}
                      {isProvisioningWallet
                        ? "Creating wallet..."
                        : "Create Sui wallet"}
                    </Button>
                    <p className="text-xs leading-6 text-muted-foreground">
                      This provisions a Sui embedded wallet for raw signing.
                    </p>
                  </div>
                ) : null}
                {selectedWallet ? (
                  <Alert className="border-black/5 bg-white/80">
                    <AlertTitle>Active signing wallet</AlertTitle>
                    <AlertDescription>
                      <span className="font-medium text-foreground">
                        {selectedWallet.address}
                      </span>
                      <span className="block text-xs text-muted-foreground">
                        Wallet ID: {selectedWallet.id}
                      </span>
                    </AlertDescription>
                  </Alert>
                ) : null}
              </div>

              <div className="grid gap-3">
                <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <label
                    htmlFor="wallet-public-key"
                    className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground"
                  >
                    Wallet public key
                  </label>
                  <Button
                    size="sm"
                    variant="outline"
                    disabled={!selectedWalletPublicKeyHex}
                    onClick={() => {
                      void handleCopyPublicKey();
                    }}
                  >
                    {hasCopiedPublicKey ? <Check /> : <Copy />}
                    {hasCopiedPublicKey ? "Copied" : "Copy public key"}
                  </Button>
                </div>
                <Textarea
                  id="wallet-public-key"
                  className="min-h-32 bg-[#fbfaf7] font-mono"
                  placeholder="Select or create a Sui wallet to view its public key."
                  value={selectedWalletPublicKeyHex}
                  readOnly
                  spellCheck={false}
                />
                <div className="grid gap-3 lg:grid-cols-2">
                  <div className="grid gap-3">
                    <div className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">
                      Cardano address
                    </div>
                    <div className="rounded-md border border-black/5 bg-[#fbfaf7] px-3 py-4">
                      {isWalletInfoLoading ? (
                        <p className="font-mono text-sm text-muted-foreground">
                          Loading Cardano address...
                        </p>
                      ) : walletInfo?.address ? (
                        <div className="grid gap-2">
                          <p className="break-all font-mono text-sm">
                            {walletInfo.address}
                          </p>
                          <a
                            href={`https://preprod.cexplorer.io/address/${walletInfo.address}`}
                            target="_blank"
                            rel="noreferrer"
                            className="text-sm underline underline-offset-4"
                          >
                            View on CExplorer
                          </a>
                        </div>
                      ) : (
                        <p className="font-mono text-sm text-muted-foreground">
                          Select a wallet to derive its Cardano address.
                        </p>
                      )}
                    </div>
                  </div>
                  <div className="grid gap-3">
                    <div className="flex items-center justify-between gap-3">
                      <div className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground">
                        Wallet balance
                      </div>
                      <Button
                        size="sm"
                        variant="outline"
                        disabled={!selectedWalletPublicKeyHash || isWalletInfoLoading}
                        onClick={() => setWalletInfoRefreshKey((value) => value + 1)}
                      >
                        {isWalletInfoLoading ? (
                          <LoaderCircle className="animate-spin" />
                        ) : null}
                        Refresh
                      </Button>
                    </div>
                    <div className="rounded-md border border-black/5 bg-[#fbfaf7] px-3 py-4">
                      <p className="font-mono text-sm">
                        {isWalletInfoLoading
                          ? "Loading wallet balance..."
                          : formatWalletBalance(walletInfo?.balance)}
                      </p>
                    </div>
                  </div>
                </div>
                {walletInfoError ? (
                  <Alert variant="destructive">
                    <AlertTitle>Wallet lookup failed</AlertTitle>
                    <AlertDescription>{walletInfoError}</AlertDescription>
                  </Alert>
                ) : null}
              </div>

              <div className="grid gap-3">
                <div className="grid gap-3 lg:grid-cols-[minmax(0,2fr)_minmax(12rem,1fr)]">
                  <div className="grid gap-3">
                    <label
                      htmlFor="receiver-address"
                      className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground"
                    >
                      Receiver address
                    </label>
                    <Textarea
                      id="receiver-address"
                      className="min-h-32 bg-white font-mono"
                      placeholder="addr_test1..."
                      value={receiverAddress}
                      onChange={(event) => setReceiverAddress(event.target.value)}
                      spellCheck={false}
                    />
                  </div>
                  <div className="grid gap-3">
                    <label
                      htmlFor="lovelace-amount"
                      className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground"
                    >
                      Amount (lovelace)
                    </label>
                    <input
                      id="lovelace-amount"
                      type="text"
                      inputMode="numeric"
                      className="h-11 rounded-md border border-input bg-white px-3 py-2 text-sm shadow-xs outline-none transition-[color,box-shadow] placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-[3px] focus-visible:ring-ring/50"
                      placeholder="1000000"
                      value={lovelaceAmount}
                      onChange={(event) => setLovelaceAmount(event.target.value)}
                    />
                    <p className="text-xs leading-6 text-muted-foreground">
                      Use whole lovelace values only.
                    </p>
                  </div>
                </div>
              </div>

              <div className="flex flex-col gap-3">
                <Button
                  size="lg"
                  disabled={
                    isSubmittingRequest ||
                    eligibleWallets.length === 0 ||
                    !selectedWalletPublicKeyHash
                  }
                  onClick={handleGenerateTransaction}
                >
                  {isSubmittingRequest ? (
                    <LoaderCircle className="animate-spin" />
                  ) : null}
                  {requestPhase === "generating"
                    ? "Generating transaction..."
                    : requestPhase === "signing"
                      ? "Signing transaction hash..."
                      : "Generate transaction"}
                </Button>
                {error ? (
                  <Alert variant="destructive">
                    <AlertTitle>Request failed</AlertTitle>
                    <AlertDescription>{error}</AlertDescription>
                  </Alert>
                ) : null}
              </div>
            </CardContent>
          </Card>
          <Card className="border-black/5 bg-[#fffdf8]/95">
            <CardHeader>
              <CardTitle>Generated Outputs</CardTitle>
              <CardDescription>
                Review the generated tx body hash, the transaction envelope, and
                the signature returned by Privy.
              </CardDescription>
            </CardHeader>
            <CardContent className="grid gap-3">
              <label
                htmlFor="tx-body-hash"
                className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground"
              >
                Tx body hash
              </label>
              <Textarea
                id="tx-body-hash"
                className="min-h-28 bg-[#fbfaf7] font-mono"
                placeholder="The generated tx body hash will appear here."
                value={generatedTransaction?.tx_body_hash ?? ""}
                readOnly
                spellCheck={false}
              />
              <label
                htmlFor="generated-transaction-cbor"
                className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground"
              >
                Generated transaction cborHex
              </label>
              <Textarea
                id="generated-transaction-cbor"
                className="min-h-40 bg-[#fbfaf7] font-mono"
                placeholder="The generated transaction envelope will appear here."
                value={generatedTransaction?.transaction.cborHex ?? ""}
                readOnly
                spellCheck={false}
              />
              <label
                htmlFor="signature"
                className="text-xs font-semibold uppercase tracking-[0.18em] text-muted-foreground"
              >
                Signature
              </label>
              <Textarea
                id="signature"
                className="min-h-56 bg-[#fbfaf7] font-mono"
                placeholder="The signature returned by raw_sign will appear here."
                value={signature}
                readOnly
                spellCheck={false}
              />
            </CardContent>
          </Card>
        </div>
      </div>
    </main>
  );
}

export default App;
