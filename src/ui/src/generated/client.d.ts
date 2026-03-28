interface IAsset {
  aPolicyId: string;
  aTokenName: string;
}

interface IAssetAmount {
  asset_id: string;
  amount: number;
}

interface IAssetEntry {
  asset: string;
  amount: number;
}

interface IDeposit {
  minimum_lp: number;
}

interface IExpirySetting {
  expired_time: number;
  max_cancellation_tip: number;
}

interface IMinSwapAssetAmount {
  asset_id: string;
  amount: number;
}

interface IMinSwapStep {
  address: string;
  locked_value: MinSwapAssetAmount[];
  canceller: AuthorizationMethod;
  refund_receiver_datum: ExtraDatum;
  success_receiver_datum: ExtraDatum;
  lp_asset: string;
  step: any;
  max_batcher_fee: number;
  expired_options: ExpirySetting | null;
}

interface IMuesliSwapAssetAmount {
  asset_id: string;
  amount: number;
}

interface IMuesliSwapStep {
  address: string;
  locked_value: MuesliSwapAssetAmount[];
  sender: string;
  receiver_datum_hash: string | null;
  step: OrderStep;
  batcher_fee: number;
  output_ada: number;
  pool_nft_token_name: string;
}

interface INetworkIdResponse {
  network_id: NetworkIdKind;
  network_magic: number | null;
}

interface IOneSideDeposit {
  desired_coin: Asset;
  minimum_lp: number;
}

interface IOutputReference {
  orTransactionId: string;
  orOutputIndex: number;
}

interface IPulseAssetAmount {
  asset_id: string;
  amount: number;
}

interface IPulseStep {
  address: string;
  locked_value: PulseAssetAmount[];
  order: PulseOrder;
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

interface ISendToAddressStep {
  destination: string;
  inline_datum: string | null;
}

interface ISundaeAMMStep {
  address: string;
  pool_ident: string | null;
  max_protocol_fee: number;
  locked_value: AssetAmount[];
  order: Order;
  extension: string;
}

interface ITransactionFlowRequest {
  user_funds: string[];
  steps: TxFlowStep[];
  final_step: SendToAddressStep;
}

interface IWalletInfo {
  address: string;
  balance: [string, number][];
}

interface IWithdraw {
  minimum_coin_a: number;
  minimum_coin_b: number;
}

type Asset = IAsset;

type AssetAmount = IAssetAmount;

type AssetEntry = IAssetEntry;

type AuthorizationMethod = {"signature": ISignature} | {"spend_script": ISpendScript} | {"withdraw_script": IWithdrawScript} | {"mint_script": IMintScript};

type ExpirySetting = IExpirySetting;

type ExtraDatum = {"no_datum": INoDatum} | {"datum_hash": IDatumHash} | {"inline_datum": IInlineDatum};

type IDatumHash = string;

type IDeposit = [AssetAmount, AssetAmount];

type IDonation = [AssetAmount, AssetAmount];

type IInlineDatum = string;

type IMinSwap = MinSwapStep;

type IMintScript = string;

type IMuesliSwap = MuesliSwapStep;

type INoDatum = void[];

type IPulse = PulseStep;

type IPulseBurnLP = void[];

type IPulseInitLP = void[];

type IPulseMergeSY = void[];

type IPulseMintLP = void[];

type IPulseSplitSY = void[];

type IPulseStakeYT = OutputReference;

type IPulseSwapExactPTForSY = number;

type IPulseSwapExactSYForPT = number;

type IPulseSwapExactSYForYT = number;

type IPulseSwapExactYTForSY = number;

type IPulseWithdrawYTReward = OutputReference;

type IRecord = string;

type ISendToAddress = SendToAddressStep;

type ISignature = string;

type ISpendScript = string;

type IStrategy = StrategyAuthorization;

type IStrategyScript = string;

type IStrategySignature = string;

type ISundaeAMM = SundaeAMMStep;

type ISwap = [AssetAmount, AssetAmount];

type IWithdrawScript = string;

type IWithdrawal = AssetAmount;

type MinSwapAssetAmount = IMinSwapAssetAmount;

type MinSwapStep = IMinSwapStep;

type MuesliSwapAssetAmount = IMuesliSwapAssetAmount;

type MuesliSwapStep = IMuesliSwapStep;

type NetworkIdKind = "preprod" | "preview" | "mainnet" | "custom";

type NetworkIdResponse = INetworkIdResponse;

type Order = {"strategy": IStrategy} | {"swap": ISwap} | {"deposit": IDeposit} | {"withdrawal": IWithdrawal} | {"donation": IDonation} | {"record": IRecord};

type OrderStep = {"deposit": IDeposit} | {"withdraw": IWithdraw} | {"one_side_deposit": IOneSideDeposit};

type OutputReference = IOutputReference;

type PulseAssetAmount = IPulseAssetAmount;

type PulseOrder = {"split_sy": IPulseSplitSY} | {"merge_sy": IPulseMergeSY} | {"init_lp": IPulseInitLP} | {"mint_lp": IPulseMintLP} | {"burn_lp": IPulseBurnLP} | {"swap_exact_sy_for_pt": IPulseSwapExactSYForPT} | {"swap_exact_pt_for_sy": IPulseSwapExactPTForSY} | {"swap_exact_yt_for_sy": IPulseSwapExactYTForSY} | {"swap_exact_sy_for_yt": IPulseSwapExactSYForYT} | {"withdraw_yt_reward": IPulseWithdrawYTReward} | {"stake_yt": IPulseStakeYT};

type PulseStep = IPulseStep;

type RawSignArgs = IRawSignArgs;

type RawSignResponse = IRawSignResponse;

type SendFundsRequest = ISendFundsRequest;

type SendToAddressStep = ISendToAddressStep;

type StrategyAuthorization = {"strategy_signature": IStrategySignature} | {"strategy_script": IStrategyScript};

type SundaeAMMStep = ISundaeAMMStep;

type TransactionFlowRequest = ITransactionFlowRequest;

type TxFlowStep = {"send_to_address": ISendToAddress} | {"min_swap": IMinSwap} | {"pulse": IPulse} | {"muesli_swap": IMuesliSwap} | {"sundae_amm": ISundaeAMM};

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

type TransactionFlowResponseDummy = ITransactionFlowResponseDummy;

interface ITransactionFlowResponseDummy {
  final_destination: string;
  transaction: ApiTxDummy;
}