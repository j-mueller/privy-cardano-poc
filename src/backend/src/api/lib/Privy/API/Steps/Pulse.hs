{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Privy.API.Steps.Pulse (
    PulseAssetAmount (..),
    OutputReference.OutputReference (..),
    PulseOrder (..),
    PulseStep (..),
    buildPulseStep,
) where

import Cardano.Address.Aiken qualified as Aiken
import Cardano.Api qualified as C
import Cardano.Ledger.BaseTypes qualified as LedgerBase
import Cardano.Ledger.Credential qualified as Ledger
import Cardano.Protocol.Pulse.Common qualified as PulseCommon
import Cardano.Protocol.Pulse.Order qualified as Pulse
import Cardano.Transaction.OutputReference qualified as OutputReference
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import GHC.Exts (fromList)
import GHC.Generics (Generic)
import PlutusTx qualified
import Privy.API.SerialiseAddress (SerialiseAddress (..))
import Privy.API.Steps.StepResult (StepResult (..))
import Privy.API.Utils (jsonOptions)
import Privy.Env.Operator qualified as Operator
import Privy.Orphans ()

data PulseAssetAmount
    = PulseAssetAmount
    { puaaAssetId :: C.AssetId
    , puaaAmount :: C.Quantity
    }
    deriving stock (Eq, Show, Generic)

data PulseOrder
    = PulseSplitSY
    | PulseMergeSY
    | PulseInitLP
    | PulseMintLP
    | PulseBurnLP
    | PulseSwapExactSYForPT Integer
    | PulseSwapExactPTForSY Integer
    | PulseSwapExactYTForSY Integer
    | PulseSwapExactSYForYT Integer
    | PulseWithdrawYTReward OutputReference.OutputReference
    | PulseStakeYT (Maybe OutputReference.OutputReference)
    deriving stock (Eq, Show, Generic)

data PulseStep
    = PulseStep
    { pusAddress :: SerialiseAddress (C.Address C.ShelleyAddr)
    , pusLockedValue :: [PulseAssetAmount]
    , pusOrder :: PulseOrder
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON PulseAssetAmount where
    toJSON = Aeson.genericToJSON (jsonOptions 4)
    toEncoding = Aeson.genericToEncoding (jsonOptions 4)

instance FromJSON PulseAssetAmount where
    parseJSON = Aeson.genericParseJSON (jsonOptions 4)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 4}) ''PulseAssetAmount)

instance Schema.ToSchema PulseAssetAmount where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions (jsonOptions 4))

pulseOrderOptions :: Aeson.Options
pulseOrderOptions =
    Aeson.defaultOptions
        { Aeson.constructorTagModifier = Aeson.camelTo2 '_' . drop 5
        , Aeson.sumEncoding = Aeson.ObjectWithSingleField
        }

instance ToJSON PulseOrder where
    toJSON = Aeson.genericToJSON pulseOrderOptions
    toEncoding = Aeson.genericToEncoding pulseOrderOptions

instance FromJSON PulseOrder where
    parseJSON = Aeson.genericParseJSON pulseOrderOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.constructorTagModifier = Aeson.camelTo2 '_' . drop 5, Aeson.sumEncoding = Aeson.ObjectWithSingleField}) ''PulseOrder)

instance Schema.ToSchema PulseOrder where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions pulseOrderOptions)

instance ToJSON PulseStep where
    toJSON = Aeson.genericToJSON (jsonOptions 3)
    toEncoding = Aeson.genericToEncoding (jsonOptions 3)

instance FromJSON PulseStep where
    parseJSON = Aeson.genericParseJSON (jsonOptions 3)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3}) ''PulseStep)

instance Schema.ToSchema PulseStep where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions (jsonOptions 3))

buildPulseStep ::
    forall era.
    Operator.OperatorEnv era ->
    StepResult C.ScriptData ->
    PulseStep ->
    StepResult Pulse.OrderDatum
buildPulseStep Operator.OperatorEnv{Operator.bteOperator = (paymentKeyHash, stakeRef)} nextStep PulseStep{pusAddress, pusLockedValue, pusOrder} =
    StepResult
        { srDatum = Just (toPulseOrder paymentKeyHash stakeRef nextStep pusOrder)
        , srAddress = unSerialiseAddress pusAddress
        , srValue = foldMap assetAmountValue pusLockedValue
        }

toPulseOrder ::
    C.Hash C.PaymentKey ->
    C.StakeAddressReference ->
    StepResult C.ScriptData ->
    PulseOrder ->
    Pulse.OrderDatum
toPulseOrder paymentKeyHash stakeRef nextStep = \case
    PulseSplitSY ->
        Pulse.OSplitSY owner receiveAddress receiveDatum receiveAddress receiveDatum
    PulseMergeSY ->
        Pulse.OMergeSY owner receiveAddress receiveDatum
    PulseInitLP ->
        Pulse.OInitLP owner (ownerStakeKeyFromReference stakeRef)
    PulseMintLP ->
        Pulse.OMintLP owner receiveAddress receiveDatum
    PulseBurnLP ->
        Pulse.OBurnLP owner receiveAddress receiveDatum receiveAddress receiveDatum
    PulseSwapExactSYForPT minimumOut ->
        Pulse.OSwapExactSYForPT owner receiveAddress receiveDatum minimumOut
    PulseSwapExactPTForSY minimumOut ->
        Pulse.OSwapExactPTForSY owner receiveAddress receiveDatum minimumOut
    PulseSwapExactYTForSY minimumOut ->
        Pulse.OSwapExactYTForSY owner receiveAddress receiveDatum minimumOut
    PulseSwapExactSYForYT minimumOut ->
        Pulse.OSwapExactSYForYT owner receiveAddress receiveDatum minimumOut
    PulseWithdrawYTReward outputReference ->
        Pulse.OWithdrawYTReward owner outputReference
    PulseStakeYT maybeOutputReference ->
        Pulse.OStakeYT owner maybeOutputReference
  where
    owner = PulseCommon.PubKeyHash paymentKeyHash
    receiveAddress = aikenAddressFromAddress (srAddress nextStep)
    receiveDatum =
        fmap (\datum -> PlutusTx.dataToBuiltinData $ C.toPlutusData datum) (srDatum nextStep)

ownerStakeKeyFromReference :: C.StakeAddressReference -> Maybe PulseCommon.PubKeyHash
ownerStakeKeyFromReference = \case
    C.StakeAddressByValue (C.StakeCredentialByKey stakeKeyHash) ->
        Just . PulseCommon.PubKeyHash $ castStakeKeyHash stakeKeyHash
    _ ->
        Nothing

aikenAddressFromAddress :: C.Address C.ShelleyAddr -> Aiken.AikenAddress
aikenAddressFromAddress = \case
    C.ShelleyAddress _ paymentCredential stakeReference ->
        Aiken.AikenAddress
            { Aiken.aaPaymentCredential = aikenPaymentCredential $ C.fromShelleyPaymentCredential paymentCredential
            , Aiken.aaStakeCredential = aikenStakeCredential $ C.fromShelleyStakeReference stakeReference
            }

aikenPaymentCredential :: C.PaymentCredential -> Aiken.Credential
aikenPaymentCredential = \case
    C.PaymentCredentialByKey keyHash -> Aiken.VerificationKeyCredential keyHash
    C.PaymentCredentialByScript scriptHash -> Aiken.ScriptCredential scriptHash

aikenStakeCredential :: C.StakeAddressReference -> Maybe Aiken.StakeCredential
aikenStakeCredential = \case
    C.NoStakeAddress -> Nothing
    C.StakeAddressByValue credential -> Just $ Aiken.Inline $ aikenStakeCredentialValue credential
    C.StakeAddressByPointer ptr ->
        let Ledger.Ptr (Ledger.SlotNo32 slotNumber) txIx certIx = C.unStakeAddressPointer ptr
         in Just $
                Aiken.Pointer
                    { Aiken.pointerSlotNumber = fromIntegral slotNumber
                    , Aiken.pointerTransactionIndex = fromIntegral (LedgerBase.unTxIx txIx)
                    , Aiken.pointerCertificateIndex = fromIntegral (LedgerBase.unCertIx certIx)
                    }

aikenStakeCredentialValue :: C.StakeCredential -> Aiken.Credential
aikenStakeCredentialValue = \case
    C.StakeCredentialByKey keyHash -> Aiken.VerificationKeyCredential $ castStakeKeyHash keyHash
    C.StakeCredentialByScript scriptHash -> Aiken.ScriptCredential scriptHash

castStakeKeyHash :: C.Hash C.StakeKey -> C.Hash C.PaymentKey
castStakeKeyHash stakeKeyHash =
    either (error . show) id $
        C.deserialiseFromRawBytes (C.AsHash C.AsPaymentKey) (C.serialiseToRawBytes stakeKeyHash)

assetAmountValue :: PulseAssetAmount -> C.Value
assetAmountValue PulseAssetAmount{puaaAssetId, puaaAmount = C.Quantity quantity} =
    case puaaAssetId of
        C.AdaAssetId -> C.lovelaceToValue (fromInteger quantity)
        _ -> fromList [(puaaAssetId, C.Quantity quantity)]
