interface IWalletInfo {
  address: string;
  balance: [string, number][];
}

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