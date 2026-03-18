interface IWalletInfo {
  address: string;
  balance: [string, number][];
}

type WalletInfo = IWalletInfo;