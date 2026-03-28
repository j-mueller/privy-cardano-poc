{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE UndecidableInstances #-}

module Privy.API.Steps (
    BuildTxAPI,
    TransactionFlowRequest (..),
    TransactionFlowResponse (..),
    TransactionFlowError (..),
    AsTransactionFlowError (..),
    TxFlowStep (..),
    MinSwapStep (..),
    PulseStep (..),
    MuesliSwapStep (..),
    SendToAddressStep (..),
    SundaeAMMStep (..),
    StepResult (..),
    toTxOut,
    txFlowTypeScriptExtraTypes,
    serve,
    buildTx,
    mkFlowStep,
) where

import Cardano.Api qualified as C
import Control.Lens (makeClassyPrisms)
import Control.Monad.Error.Lens (throwing_)
import Control.Monad.Except (MonadError)
import Convex.BuildTx qualified as BuildTx
import Convex.CardanoApi.Lenses (emptyTxOut)
import Convex.Class (MonadBlockchain, MonadUtxoQuery)
import Convex.Class qualified as Chain
import Convex.CoinSelection qualified as CoinSelection
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (TSType (..), TypeScript (..), deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import Data.Proxy (Proxy (..))
import Data.Set qualified as Set
import Data.Typeable (Typeable)
import GHC.Generics (Generic)
import PlutusTx qualified
import Privy.API.SerialiseAddress (SerialiseAddress (..))
import Privy.API.SerialisedPlutusDatum (SerialisedPlutusDatum (..))
import Privy.API.Steps.MinSwap (MinSwapStep (..), buildMinSwapStep)
import Privy.API.Steps.MuesliSwap (MuesliSwapStep (..), buildMuesliSwapStep)
import Privy.API.Steps.Pulse (PulseStep (..), buildPulseStep)
import Privy.API.Steps.SendToAddress (SendToAddressStep (..), buildSendToAddressStep)
import Privy.API.Steps.StepResult (StepResult (..), toTxOut)
import Privy.API.Steps.SundaeAMM (SundaeAMMStep (..), buildSundaeAMMStep)
import Privy.API.SubmitTx (ApiTx, ApiTxDummy, apiTx, txApiTypeScriptExtraTypes)
import Privy.API.Utils (jsonOptions)
import Privy.Env.Operator (OperatorEnv (..))
import Servant.API (JSON, Post, ReqBody, type (:>))
import Servant.Server (ServerT)

data TransactionFlowError
    = NoUserFunds
    | NotAPublicKeyAddress
    deriving stock (Eq, Show)

makeClassyPrisms ''TransactionFlowError

data TxFlowStep
    = SendToAddress SendToAddressStep
    | MinSwap MinSwapStep
    | Pulse PulseStep
    | MuesliSwap MuesliSwapStep
    | SundaeAMM SundaeAMMStep
    deriving stock (Eq, Show, Generic)

txFlowStepOptions :: Aeson.Options
txFlowStepOptions =
    Aeson.defaultOptions
        { Aeson.constructorTagModifier = Aeson.camelTo2 '_' . drop 0
        , Aeson.sumEncoding = Aeson.ObjectWithSingleField
        }

instance ToJSON TxFlowStep where
    toJSON = Aeson.genericToJSON txFlowStepOptions
    toEncoding = Aeson.genericToEncoding txFlowStepOptions

instance FromJSON TxFlowStep where
    parseJSON = Aeson.genericParseJSON txFlowStepOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.constructorTagModifier = Aeson.camelTo2 '_' . drop 0, Aeson.sumEncoding = Aeson.ObjectWithSingleField}) ''TxFlowStep)

instance Schema.ToSchema TxFlowStep where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions txFlowStepOptions)

data TransactionFlowRequest
    = TransactionFlowRequest
    { tfrUserFunds :: [SerialiseAddress (C.Address C.ShelleyAddr)]
    , tfrSteps :: [TxFlowStep]
    , tfrFinalStep :: SendToAddressStep
    }
    deriving stock (Eq, Show, Generic)

data TransactionFlowResponse era
    = TransactionFlowResponse
    { tfrFinalDestination :: SerialiseAddress (C.Address C.ShelleyAddr)
    , tfrTransaction :: ApiTx era
    }
    deriving stock (Eq, Show, Generic)

data TransactionFlowResponseDummy
    = TransactionFlowResponseDummy
    { tfrdFinalDestination :: SerialiseAddress (C.Address C.ShelleyAddr)
    , tfrdTransaction :: ApiTxDummy
    }
    deriving stock (Generic)

type BuildTxAPI era =
    "build_tx" :> ReqBody '[JSON] TransactionFlowRequest :> Post '[JSON] (TransactionFlowResponse era)

instance ToJSON TransactionFlowRequest where
    toJSON = Aeson.genericToJSON (jsonOptions 3)
    toEncoding = Aeson.genericToEncoding (jsonOptions 3)

instance FromJSON TransactionFlowRequest where
    parseJSON = Aeson.genericParseJSON (jsonOptions 3)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3}) ''TransactionFlowRequest)

instance Schema.ToSchema TransactionFlowRequest where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions (jsonOptions 3))

transactionFlowResponseOptions :: Aeson.Options
transactionFlowResponseOptions = jsonOptions 3

instance (C.IsShelleyBasedEra era) => ToJSON (TransactionFlowResponse era) where
    toJSON = Aeson.genericToJSON transactionFlowResponseOptions
    toEncoding = Aeson.genericToEncoding transactionFlowResponseOptions

instance (C.IsShelleyBasedEra era) => FromJSON (TransactionFlowResponse era) where
    parseJSON = Aeson.genericParseJSON transactionFlowResponseOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 4}) ''TransactionFlowResponseDummy)

instance (Typeable era) => TypeScript (TransactionFlowResponse era) where
    getTypeScriptType _ = getTypeScriptType (Proxy @TransactionFlowResponseDummy)

instance (C.IsShelleyBasedEra era) => Schema.ToSchema (TransactionFlowResponse era) where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions transactionFlowResponseOptions)

txFlowTypeScriptExtraTypes :: [TSType]
txFlowTypeScriptExtraTypes =
    txApiTypeScriptExtraTypes
        <> [TSType (Proxy @TransactionFlowResponseDummy)]

serve ::
    forall era err m.
    ( MonadBlockchain era m
    , MonadError err m
    , MonadUtxoQuery m
    , C.IsBabbageBasedEra era
    , AsTransactionFlowError err
    , CoinSelection.AsBalancingError err era
    , CoinSelection.AsCoinSelectionError err
    ) =>
    ServerT (BuildTxAPI era) m
serve = buildTx

buildTx ::
    forall era err m.
    ( MonadBlockchain era m
    , MonadError err m
    , MonadUtxoQuery m
    , C.IsBabbageBasedEra era
    , AsTransactionFlowError err
    , CoinSelection.AsBalancingError err era
    , CoinSelection.AsCoinSelectionError err
    ) =>
    TransactionFlowRequest ->
    m (TransactionFlowResponse era)
buildTx TransactionFlowRequest{tfrUserFunds, tfrSteps, tfrFinalStep = s@SendToAddressStep{stasDestination}} =
    case fmap unSerialiseAddress tfrUserFunds of
        [] ->
            throwing_ _NoUserFunds
        senders@(sender : _) -> do
            operatorEnv <- operatorEnvFromAddresses @era senders
            senderUtxos <-
                Chain.utxosByPaymentCredentials $
                    Set.fromList $
                        paymentCredentialFromAddress <$> senders
            let flowResult =
                    foldr
                        (\step next -> mkFlowStep operatorEnv next step)
                        (serialisedDatumStepResult $ buildSendToAddressStep s)
                        tfrSteps
            params <- Chain.queryProtocolParameters
            (_, txBuilder) <- BuildTx.runBuildTxT $ do
                BuildTx.addOutput $ toTxOut flowResult
                BuildTx.setMinAdaDepositAll params
            (balancedTxBody, _) <-
                CoinSelection.balanceTx
                    mempty
                    (returnOutputForAddress sender)
                    senderUtxos
                    txBuilder
                    CoinSelection.TrailingChange
            pure $
                TransactionFlowResponse
                    { tfrFinalDestination = stasDestination
                    , tfrTransaction = apiTx $ CoinSelection.signBalancedTxBody [] balancedTxBody
                    }

mkFlowStep ::
    forall era.
    OperatorEnv era ->
    StepResult C.ScriptData ->
    TxFlowStep ->
    StepResult C.ScriptData
mkFlowStep operatorEnv result = \case
    SendToAddress m -> serialisedDatumStepResult $ buildSendToAddressStep m
    MinSwap m -> toScriptDataStepResult $ buildMinSwapStep result m
    Pulse m -> toScriptDataStepResult $ buildPulseStep operatorEnv result m
    MuesliSwap m -> toScriptDataStepResult $ buildMuesliSwapStep result m
    SundaeAMM m -> toScriptDataStepResult $ buildSundaeAMMStep operatorEnv result m

serialisedDatumStepResult :: StepResult SerialisedPlutusDatum -> StepResult C.ScriptData
serialisedDatumStepResult = fmap unSerialisedPlutusDatum

toScriptDataStepResult ::
    (PlutusTx.ToData a) =>
    StepResult a ->
    StepResult C.ScriptData
toScriptDataStepResult = fmap (C.fromPlutusData . PlutusTx.toData . PlutusTx.toBuiltinData)

operatorEnvFromAddresses ::
    forall era err m.
    (MonadError err m, AsTransactionFlowError err) =>
    [C.Address C.ShelleyAddr] ->
    m (OperatorEnv era)
operatorEnvFromAddresses = \case
    [] -> throwing_ _NoUserFunds
    (sender : _) -> do
        operator <- operatorFromAddress sender
        pure $
            OperatorEnv
                { bteOperator = operator
                , bteOperatorUtxos = mempty
                }

operatorFromAddress ::
    forall err m.
    (MonadError err m, AsTransactionFlowError err) =>
    C.Address C.ShelleyAddr ->
    m (C.Hash C.PaymentKey, C.StakeAddressReference)
operatorFromAddress = \case
    C.ShelleyAddress _ (C.fromShelleyPaymentCredential -> C.PaymentCredentialByKey paymentKey) stakeRef ->
        pure (paymentKey, C.fromShelleyStakeReference stakeRef)
    _ ->
        throwing_ _NotAPublicKeyAddress

paymentCredentialFromAddress :: C.Address C.ShelleyAddr -> C.PaymentCredential
paymentCredentialFromAddress = \case
    C.ShelleyAddress _ paymentCredential _ -> C.fromShelleyPaymentCredential paymentCredential

returnOutputForAddress ::
    forall era.
    (C.IsBabbageBasedEra era) =>
    C.Address C.ShelleyAddr ->
    C.TxOut C.CtxTx era
returnOutputForAddress address =
    emptyTxOut $
        C.AddressInEra (C.ShelleyAddressInEra C.shelleyBasedEra) address
