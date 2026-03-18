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

type TextEnvelopeJsonDummy = ITextEnvelopeJsonDummy;

interface ITextEnvelopeJsonDummy {
  cborHex: string;
  description: string;
  type: string;
}