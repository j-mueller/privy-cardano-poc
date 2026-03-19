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

interface IWalletInfo {
  address: string;
  balance: [string, number][];
}

type RawSignArgs = IRawSignArgs;

type RawSignResponse = IRawSignResponse;

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