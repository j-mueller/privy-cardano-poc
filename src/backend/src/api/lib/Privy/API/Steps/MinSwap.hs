{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Privy.API.Steps.MinSwap (
    MinSwapAssetAmount (..),
    MinSwap.AuthorizationMethod (..),
    MinSwap.ExtraDatum (..),
    MinSwap.Direction (..),
    MinSwap.Killable (..),
    MinSwap.DepositAmount (..),
    MinSwap.SwapAmount (..),
    MinSwap.WithdrawAmount (..),
    MinSwap.Route (..),
    MinSwap.Step (..),
    MinSwap.ExpirySetting (..),
    MinSwapStep (..),
    buildMinSwapStep,
) where

import Cardano.Address.Plutus qualified as PlutusAddress
import Cardano.Api qualified as C
import Cardano.Protocol.MinSwap.Order qualified as MinSwap
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import GHC.Exts (fromList)
import GHC.Generics (Generic)
import Privy.API.SerialiseAddress (SerialiseAddress (..))
import Privy.API.Steps.StepResult (StepResult (..))
import Privy.API.Utils (jsonOptions)
import Privy.Orphans ()

data MinSwapAssetAmount
    = MinSwapAssetAmount
    { msaaAssetId :: C.AssetId
    , msaaAmount :: C.Quantity
    }
    deriving stock (Eq, Show, Generic)

data MinSwapStep
    = MinSwapStep
    { mssAddress :: SerialiseAddress (C.Address C.ShelleyAddr)
    , mssLockedValue :: [MinSwapAssetAmount]
    , mssCanceller :: MinSwap.AuthorizationMethod
    , mssRefundReceiverDatum :: MinSwap.ExtraDatum
    , mssSuccessReceiverDatum :: MinSwap.ExtraDatum
    , mssLpAsset :: C.AssetId
    , mssStep :: MinSwap.Step
    , mssMaxBatcherFee :: C.Quantity
    , mssExpiredOptions :: Maybe MinSwap.ExpirySetting
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON MinSwapAssetAmount where
    toJSON = Aeson.genericToJSON (jsonOptions 4)
    toEncoding = Aeson.genericToEncoding (jsonOptions 4)

instance FromJSON MinSwapAssetAmount where
    parseJSON = Aeson.genericParseJSON (jsonOptions 4)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 4}) ''MinSwapAssetAmount)

instance Schema.ToSchema MinSwapAssetAmount where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions (jsonOptions 4))

instance ToJSON MinSwapStep where
    toJSON = Aeson.genericToJSON (jsonOptions 3)
    toEncoding = Aeson.genericToEncoding (jsonOptions 3)

instance FromJSON MinSwapStep where
    parseJSON = Aeson.genericParseJSON (jsonOptions 3)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3}) ''MinSwapStep)

instance Schema.ToSchema MinSwapStep where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions (jsonOptions 3))

buildMinSwapStep ::
    StepResult C.ScriptData ->
    MinSwapStep ->
    StepResult (MinSwap.MinSwapV2Order PlutusAddress.PlutusAddress)
buildMinSwapStep nextStep MinSwapStep{mssAddress, mssLockedValue, mssCanceller, mssRefundReceiverDatum, mssSuccessReceiverDatum, mssLpAsset, mssStep, mssMaxBatcherFee, mssExpiredOptions} =
    StepResult
        { srDatum =
            Just
                MinSwap.MinSwapV2Order
                    { MinSwap.msCanceller = mssCanceller
                    , MinSwap.msRefundReceiver = receiverAddress
                    , MinSwap.msRefundReceiverDatum = mssRefundReceiverDatum
                    , MinSwap.msSuccessReceiver = receiverAddress
                    , MinSwap.msSuccessReceiverDatum = mssSuccessReceiverDatum
                    , MinSwap.msLpAsset = mssLpAsset
                    , MinSwap.msStep = mssStep
                    , MinSwap.msMaxBatcherFee = mssMaxBatcherFee
                    , MinSwap.msExpiredOptions = mssExpiredOptions
                    }
        , srAddress = unSerialiseAddress mssAddress
        , srValue = foldMap assetAmountValue mssLockedValue
        }
  where
    receiverAddress = PlutusAddress.fromAddress (srAddress nextStep)

assetAmountValue :: MinSwapAssetAmount -> C.Value
assetAmountValue MinSwapAssetAmount{msaaAssetId, msaaAmount = C.Quantity quantity} =
    case msaaAssetId of
        C.AdaAssetId -> C.lovelaceToValue (fromInteger quantity)
        _ -> fromList [(msaaAssetId, C.Quantity quantity)]
