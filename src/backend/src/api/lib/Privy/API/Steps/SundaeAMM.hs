{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Privy.API.Steps.SundaeAMM (
    Sundae.AssetAmount (..),
    Sundae.StrategyAuthorization (..),
    Sundae.Order (..),
    SundaeAMMStep (..),
    buildSundaeAMMStep,
) where

import Cardano.Api qualified as C
import Cardano.Ledger.BaseTypes qualified as LedgerBase
import Cardano.Ledger.Credential qualified as Ledger
import Cardano.Protocol.Sundae.Order qualified as Sundae
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import GHC.Exts (fromList)
import GHC.Generics (Generic)
import PlutusTx qualified
import PlutusTx.Builtins qualified as Builtins
import Privy.API.SerialiseAddress (SerialiseAddress (..))
import Privy.API.Steps.StepResult (StepResult (..))
import Privy.API.Utils (jsonOptions)
import Privy.Env.Operator qualified as Operator
import Privy.Orphans ()

data SundaeAMMStep
    = SundaeAMMStep
    { samsAddress :: SerialiseAddress (C.Address C.ShelleyAddr)
    , samsPoolIdent :: Maybe Builtins.BuiltinByteString
    , samsMaxProtocolFee :: C.Quantity
    , samsLockedValue :: [Sundae.AssetAmount]
    , samsOrder :: Sundae.Order
    , samsExtension :: Builtins.BuiltinByteString
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON SundaeAMMStep where
    toJSON = Aeson.genericToJSON (jsonOptions 4)
    toEncoding = Aeson.genericToEncoding (jsonOptions 4)

instance FromJSON SundaeAMMStep where
    parseJSON = Aeson.genericParseJSON (jsonOptions 4)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 4}) ''SundaeAMMStep)

instance Schema.ToSchema SundaeAMMStep where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions (jsonOptions 4))

buildSundaeAMMStep ::
    forall era.
    Operator.OperatorEnv era ->
    StepResult C.ScriptData ->
    SundaeAMMStep ->
    StepResult Sundae.SundaeOrderDatum
buildSundaeAMMStep Operator.OperatorEnv{Operator.bteOperator = (paymentKeyHash, _)} nextStep SundaeAMMStep{samsAddress, samsPoolIdent, samsMaxProtocolFee, samsLockedValue, samsOrder, samsExtension} =
    StepResult
        { srDatum =
            Just
                Sundae.SundaeOrderDatum
                    { Sundae.soPoolIdent = samsPoolIdent
                    , Sundae.soOwner = Sundae.Signature paymentKeyHash
                    , Sundae.soMaxProtocolFee = samsMaxProtocolFee
                    , Sundae.soDestination = destinationFromStepResult nextStep
                    , Sundae.soDetails = samsOrder
                    , Sundae.soExtension = samsExtension
                    }
        , srAddress = unSerialiseAddress samsAddress
        , srValue = foldMap assetAmountValue samsLockedValue
        }

destinationFromStepResult :: StepResult C.ScriptData -> Sundae.Destination
destinationFromStepResult StepResult{srAddress, srDatum} =
    Sundae.FixedDestination
        (sundaeAddressFromAddress srAddress)
        ( case srDatum of
            Nothing -> Sundae.NoDatum
            Just datum -> Sundae.InlineDatum $ PlutusTx.dataToBuiltinData $ C.toPlutusData datum
        )

sundaeAddressFromAddress :: C.Address C.ShelleyAddr -> Sundae.SundaeAddress
sundaeAddressFromAddress = \case
    C.ShelleyAddress _ paymentCredential stakeReference ->
        Sundae.SundaeAddress
            { Sundae.saPaymentCredential = credentialFromPayment (C.fromShelleyPaymentCredential paymentCredential)
            , Sundae.saStakeCredential = stakeCredentialFromReference (C.fromShelleyStakeReference stakeReference)
            }

credentialFromPayment :: C.PaymentCredential -> Sundae.Credential
credentialFromPayment = \case
    C.PaymentCredentialByKey keyHash -> Sundae.VerificationKeyCredential keyHash
    C.PaymentCredentialByScript scriptHash -> Sundae.ScriptCredential scriptHash

stakeCredentialFromReference :: C.StakeAddressReference -> Maybe Sundae.StakingCredential
stakeCredentialFromReference = \case
    C.NoStakeAddress -> Nothing
    C.StakeAddressByValue credential -> Just $ Sundae.Inline $ credentialFromStake credential
    C.StakeAddressByPointer ptr ->
        let Ledger.Ptr (Ledger.SlotNo32 slotNumber) txIx certIx = C.unStakeAddressPointer ptr
         in Just $
                Sundae.Pointer
                    { Sundae.pointerSlotNumber = fromIntegral slotNumber
                    , Sundae.pointerTransactionIndex = fromIntegral (LedgerBase.unTxIx txIx)
                    , Sundae.pointerCertificateIndex = fromIntegral (LedgerBase.unCertIx certIx)
                    }

credentialFromStake :: C.StakeCredential -> Sundae.Credential
credentialFromStake = \case
    C.StakeCredentialByKey keyHash -> Sundae.VerificationKeyCredential (castStakeKeyHash keyHash)
    C.StakeCredentialByScript scriptHash -> Sundae.ScriptCredential scriptHash

castStakeKeyHash :: C.Hash C.StakeKey -> C.Hash C.PaymentKey
castStakeKeyHash stakeKeyHash =
    either (error . show) id $
        C.deserialiseFromRawBytes (C.AsHash C.AsPaymentKey) (C.serialiseToRawBytes stakeKeyHash)

assetAmountValue :: Sundae.AssetAmount -> C.Value
assetAmountValue Sundae.AssetAmount{Sundae.aaAssetId, Sundae.aaAmount = C.Quantity quantity} =
    case aaAssetId of
        C.AdaAssetId -> C.lovelaceToValue (fromInteger quantity)
        _ -> fromList [(aaAssetId, C.Quantity quantity)]
