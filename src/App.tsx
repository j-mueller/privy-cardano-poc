import { useEffect, useMemo, useState } from "react";
import {
  useAuthorizationSignature,
  usePrivy,
  useUser,
  type LinkedAccountWithMetadata,
} from "@privy-io/react-auth";
import { useCreateWallet as useCreateExtendedWallet } from "@privy-io/react-auth/extended-chains";

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

function App() {
  const { ready, authenticated, login, logout, user } = usePrivy();
  const { refreshUser } = useUser();
  const { generateAuthorizationSignature } = useAuthorizationSignature();
  const { createWallet } = useCreateExtendedWallet();
  const [transactionHex, setTransactionHex] = useState("");
  const [signatureHex, setSignatureHex] = useState("");
  const [selectedWalletId, setSelectedWalletId] = useState("");
  const [error, setError] = useState("");
  const [isSigning, setIsSigning] = useState(false);
  const [isProvisioningWallet, setIsProvisioningWallet] = useState(false);
  const [hasCopiedPublicKey, setHasCopiedPublicKey] = useState(false);

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

  const handleSign = async () => {
    setError("");
    setSignatureHex("");

    if (!selectedWalletId) {
      setError("No delegated embedded wallet is available for raw_sign.");
      return;
    }

    if (!transactionHex.trim()) {
      setError("Paste a serialized transaction in hex format first.");
      return;
    }

    setIsSigning(true);

    try {
      const authorizationSignature = await generateAuthorizationSignature({
        version: 1,
        method: "POST",
        url: `https://api.privy.io/v1/wallets/${selectedWalletId}/raw_sign`,
        body: {
          params: {
            bytes: btoa(
              transactionHex
                .trim()
                .replace(/^0x/, "")
                .match(/.{1,2}/g)!
                .map((byte) => String.fromCharCode(parseInt(byte, 16)))
                .join("")
            ),
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
          transactionHex,
          authorizationSignature: authorizationSignature.signature,
        }),
      });

      const data = (await response.json()) as RawSignResponse;

      if (!response.ok || !data.signature) {
        throw new Error(data.error ?? "raw_sign failed.");
      }

      setSignatureHex(data.signature);
    } catch (requestError) {
      const message =
        requestError instanceof Error
          ? requestError.message
          : "raw_sign failed.";
      setError(message);
    } finally {
      setIsSigning(false);
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
      <main className="min-h-screen bg-[#f3efe6] text-[#1b1813]">
        <div className="mx-auto flex min-h-screen max-w-5xl items-center justify-center px-6">
          <div className="rounded-3xl border border-black/10 bg-white/80 px-6 py-4 text-sm uppercase tracking-[0.24em]">
            Loading Privy
          </div>
        </div>
      </main>
    );
  }

  if (!authenticated) {
    return (
      <main className="min-h-screen bg-[#f3efe6] text-[#1b1813]">
        <div className="mx-auto flex min-h-screen max-w-5xl flex-col justify-center px-6 py-16">
          <div className="max-w-3xl rounded-[2rem] border border-black/10 bg-[#fffdf8] p-8 shadow-[0_24px_80px_rgba(27,24,19,0.08)] sm:p-12">
            <p className="text-xs font-semibold uppercase tracking-[0.3em] text-[#8a5a44]">
              Privy Raw Sign Demo
            </p>
            <h1 className="mt-4 max-w-2xl text-4xl leading-tight font-abc-favorit sm:text-6xl">
              Log in, paste a serialized transaction, and sign it remotely.
            </h1>
            <p className="mt-6 max-w-2xl text-base leading-7 text-black/70 sm:text-lg">
              This page signs the bytes you paste with Privy&apos;s
              <code className="mx-1 rounded bg-black/5 px-1.5 py-0.5 text-sm">
                raw_sign
              </code>
              endpoint and returns the signature as hex.
            </p>
            <button
              className="mt-10 inline-flex w-full items-center justify-center rounded-full bg-[#1b1813] px-6 py-4 text-sm font-semibold uppercase tracking-[0.18em] text-[#f8f3ea] transition hover:bg-black sm:w-auto"
              onClick={() => {
                setError("");
                login();
              }}
            >
              Log In With Privy
            </button>
          </div>
        </div>
      </main>
    );
  }

  return (
    <main className="min-h-screen bg-[#f3efe6] px-6 py-10 text-[#1b1813]">
      <div className="mx-auto max-w-5xl">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <p className="text-xs font-semibold uppercase tracking-[0.3em] text-[#8a5a44]">
              Privy Raw Sign Demo
            </p>
            <h1 className="mt-3 text-3xl leading-tight font-abc-favorit sm:text-5xl">
              Sign a serialized transaction in hex.
            </h1>
            <p className="mt-4 max-w-3xl text-sm leading-7 text-black/70 sm:text-base">
              The API route sends the transaction bytes to Privy&apos;s
              <code className="mx-1 rounded bg-black/5 px-1.5 py-0.5 text-sm">
                raw_sign
              </code>
              endpoint using a Sui embedded wallet.
              Hashing is fixed to
              <code className="mx-1 rounded bg-black/5 px-1.5 py-0.5 text-sm">
                blake2b256
              </code>
              in this demo.
            </p>
          </div>
          <button
            className="inline-flex items-center justify-center rounded-full border border-black/15 px-5 py-3 text-xs font-semibold uppercase tracking-[0.18em] text-black transition hover:bg-black hover:text-[#f8f3ea]"
            onClick={() => logout()}
          >
            Log Out
          </button>
        </div>

        <section className="mt-10 rounded-[2rem] border border-black/10 bg-[#fffdf8] p-6 shadow-[0_24px_80px_rgba(27,24,19,0.08)] sm:p-8">
          <div className="grid gap-6">
            <div className="grid gap-3">
              <label
                htmlFor="wallet-id"
                className="text-xs font-semibold uppercase tracking-[0.18em] text-black/60"
              >
                Delegated wallet
              </label>
              {eligibleWallets.length > 0 ? (
                <select
                  id="wallet-id"
                  className="rounded-2xl border border-black/10 bg-white px-4 py-3 text-sm outline-none transition focus:border-black/30"
                  value={selectedWalletId}
                  onChange={(event) => setSelectedWalletId(event.target.value)}
                >
                  {eligibleWallets.map((wallet) => (
                    <option key={wallet.id} value={wallet.id}>
                      {wallet.chainType} | {wallet.address} | {wallet.id}
                    </option>
                  ))}
                </select>
              ) : (
                <div className="rounded-2xl border border-[#b75b3b]/20 bg-[#fff5ef] px-4 py-4 text-sm leading-7 text-[#7b3219]">
                  No Sui wallet with a server wallet ID is linked to this
                  account. This demo can only call
                  <code className="mx-1 rounded bg-black/5 px-1.5 py-0.5 text-sm">
                    raw_sign
                  </code>
                  for supported non-Ethereum wallets that already have a Privy
                  wallet ID.
                </div>
              )}
              {eligibleWallets.length === 0 ? (
                <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
                  <button
                    className="inline-flex items-center justify-center rounded-full border border-black/15 px-5 py-3 text-xs font-semibold uppercase tracking-[0.18em] text-black transition hover:bg-black hover:text-[#f8f3ea] disabled:cursor-not-allowed disabled:border-black/10 disabled:text-black/40"
                    disabled={isProvisioningWallet}
                    onClick={handleProvisionWallet}
                  >
                    {isProvisioningWallet
                      ? "Creating wallet..."
                      : "Create Sui wallet"}
                  </button>
                  <p className="text-xs leading-6 text-black/50">
                    This will create a Sui embedded wallet for raw signing.
                  </p>
                </div>
              ) : null}
              {selectedWallet ? (
                <p className="text-xs leading-6 text-black/50">
                  Signing with {selectedWallet.chainType} wallet{" "}
                  {selectedWallet.address}.
                </p>
              ) : null}
            </div>

            <div className="grid gap-3">
              <label
                htmlFor="wallet-public-key"
                className="text-xs font-semibold uppercase tracking-[0.18em] text-black/60"
              >
                Wallet public key
              </label>
              <div className="flex flex-col gap-3 sm:flex-row sm:items-start">
                <textarea
                  id="wallet-public-key"
                  className="min-h-28 flex-1 rounded-[1.5rem] border border-black/10 bg-[#fbfaf7] px-4 py-4 font-mono text-sm leading-7 outline-none"
                  placeholder="Select or create a Sui wallet to view its public key."
                  value={selectedWalletPublicKeyHex}
                  readOnly
                  spellCheck={false}
                />
                <button
                  className="inline-flex items-center justify-center rounded-full border border-black/15 px-5 py-3 text-xs font-semibold uppercase tracking-[0.18em] text-black transition hover:bg-black hover:text-[#f8f3ea] disabled:cursor-not-allowed disabled:border-black/10 disabled:text-black/40"
                  disabled={!selectedWalletPublicKeyHex}
                  onClick={() => {
                    void handleCopyPublicKey();
                  }}
                >
                  {hasCopiedPublicKey ? "Copied" : "Copy public key"}
                </button>
              </div>
            </div>

            <div className="grid gap-3">
              <label
                htmlFor="transaction-hex"
                className="text-xs font-semibold uppercase tracking-[0.18em] text-black/60"
              >
                Serialized transaction hex
              </label>
              <textarea
                id="transaction-hex"
                className="min-h-52 rounded-[1.5rem] border border-black/10 bg-white px-4 py-4 font-mono text-sm leading-7 outline-none transition focus:border-black/30"
                placeholder="Paste hex bytes here. 0x prefix is optional."
                value={transactionHex}
                onChange={(event) => setTransactionHex(event.target.value)}
                spellCheck={false}
              />
            </div>

            <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
              <button
                className="inline-flex items-center justify-center rounded-full bg-[#1b1813] px-6 py-4 text-sm font-semibold uppercase tracking-[0.18em] text-[#f8f3ea] transition hover:bg-black disabled:cursor-not-allowed disabled:bg-black/25"
                disabled={isSigning || eligibleWallets.length === 0}
                onClick={handleSign}
              >
                {isSigning ? "Signing..." : "Call raw_sign"}
              </button>
              {error ? (
                <p className="text-sm leading-6 text-[#a33719]">{error}</p>
              ) : null}
            </div>

            <div className="grid gap-3">
              <label
                htmlFor="signature-hex"
                className="text-xs font-semibold uppercase tracking-[0.18em] text-black/60"
              >
                Signature hex
              </label>
              <textarea
                id="signature-hex"
                className="min-h-40 rounded-[1.5rem] border border-black/10 bg-[#fbfaf7] px-4 py-4 font-mono text-sm leading-7 outline-none"
                placeholder="The signature returned by raw_sign will appear here."
                value={signatureHex}
                readOnly
                spellCheck={false}
              />
            </div>
          </div>
        </section>
      </div>
    </main>
  );
}

export default App;
