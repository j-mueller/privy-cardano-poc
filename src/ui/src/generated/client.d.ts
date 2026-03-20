interface IAssetEntry {
  asset: string;
  amount: number;
}

interface INetworkIdResponse {
  network_id: NetworkIdKind;
  network_magic: number | null;
}

interface IRawSignArgs {
  wallet_id: string;
  payload_hex: string | null;
  transaction_hex: string | null;
  authorization_signature: string;
  hash_function: 'sha256' | 'blake2b256' | 'keccak256' | null;
}

interface IRawSignResponse {
  signature: string;
}

interface ISendFundsRequest {
  senders: string[];
  receiver: string;
  assets: AssetEntry[];
}

interface IWalletInfo {
  address: string;
  balance: [string, number][];
}

type AssetEntry = IAssetEntry;

type NetworkIdKind = "preprod" | "preview" | "mainnet" | "custom";

type NetworkIdResponse = INetworkIdResponse;

type RawSignArgs = IRawSignArgs;

type RawSignResponse = IRawSignResponse;

type SendFundsRequest = ISendFundsRequest;

type WalletInfo = IWalletInfo;

type ApiTxDummy = IApiTxDummy;

interface IApiTxDummy {
  transaction: TextEnvelopeJsonDummy;
  tx_body_hash: string;
}

type KeyWitness = IKeyWitness;

interface IKeyWitness {
  public_key: string;
  signature: string;
}

type SubmitTxArgsDummy = ISubmitTxArgsDummy;

interface ISubmitTxArgsDummy {
  transaction: TextEnvelopeJsonDummy;
  witnesses: KeyWitness[];
}

type TextEnvelopeJsonDummy = ITextEnvelopeJsonDummy;

interface ITextEnvelopeJsonDummy {
  cborHex: string;
  description: string;
  type: string;
}