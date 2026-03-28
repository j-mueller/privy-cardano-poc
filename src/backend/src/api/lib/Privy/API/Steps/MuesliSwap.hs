{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Privy.API.Steps.MuesliSwap (
    MuesliSwapAssetAmount (..),
    Muesli.OrderStep (..),
    MuesliSwapStep (..),
    buildMuesliSwapStep,
) where

import Cardano.Address.Plutus qualified as PlutusAddress
import Cardano.Api qualified as C
import Cardano.Protocol.MuesliSwap.Order qualified as Muesli
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import GHC.Exts (fromList)
import GHC.Generics (Generic)
import PlutusTx.Builtins qualified as PlutusTx
import Privy.API.SerialiseAddress (SerialiseAddress (..))
import Privy.API.Steps.StepResult (StepResult (..))
import Privy.API.Utils (jsonOptions)
import Privy.Orphans ()

data MuesliSwapAssetAmount
    = MuesliSwapAssetAmount
    { musaAssetId :: C.AssetId
    , musaAmount :: C.Quantity
    }
    deriving stock (Eq, Show, Generic)

data MuesliSwapStep
    = MuesliSwapStep
    { mussAddress :: SerialiseAddress (C.Address C.ShelleyAddr)
    , mussLockedValue :: [MuesliSwapAssetAmount]
    , mussSender :: SerialiseAddress (C.Address C.ShelleyAddr)
    , mussReceiverDatumHash :: Maybe PlutusTx.BuiltinByteString
    , mussStep :: Muesli.OrderStep
    , mussBatcherFee :: Integer
    , mussOutputAda :: Integer
    , mussPoolNftTokenName :: PlutusTx.BuiltinByteString
    }
    deriving stock (Eq, Show, Generic)

instance ToJSON MuesliSwapAssetAmount where
    toJSON = Aeson.genericToJSON (jsonOptions 4)
    toEncoding = Aeson.genericToEncoding (jsonOptions 4)

instance FromJSON MuesliSwapAssetAmount where
    parseJSON = Aeson.genericParseJSON (jsonOptions 4)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 4}) ''MuesliSwapAssetAmount)

instance Schema.ToSchema MuesliSwapAssetAmount where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions (jsonOptions 4))

instance ToJSON MuesliSwapStep where
    toJSON = Aeson.genericToJSON (jsonOptions 4)
    toEncoding = Aeson.genericToEncoding (jsonOptions 4)

instance FromJSON MuesliSwapStep where
    parseJSON = Aeson.genericParseJSON (jsonOptions 4)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 4}) ''MuesliSwapStep)

instance Schema.ToSchema MuesliSwapStep where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions (jsonOptions 4))

buildMuesliSwapStep ::
    StepResult C.ScriptData ->
    MuesliSwapStep ->
    StepResult Muesli.OrderDatum
buildMuesliSwapStep nextStep MuesliSwapStep{mussAddress, mussLockedValue, mussSender, mussReceiverDatumHash, mussStep, mussBatcherFee, mussOutputAda, mussPoolNftTokenName} =
    StepResult
        { srDatum =
            Just
                Muesli.OrderDatum
                    { Muesli.odSender = PlutusAddress.fromAddress (unSerialiseAddress mussSender)
                    , Muesli.odReceiver = PlutusAddress.fromAddress (srAddress nextStep)
                    , Muesli.odReceiverDatumHash = scriptDataHashFromBytes <$> mussReceiverDatumHash
                    , Muesli.odStep = mussStep
                    , Muesli.odBatcherFee = mussBatcherFee
                    , Muesli.odOutputADA = mussOutputAda
                    , Muesli.odPoolNftTokenName = mussPoolNftTokenName
                    , Muesli.odScriptVersion = Muesli.scriptVersion
                    }
        , srAddress = unSerialiseAddress mussAddress
        , srValue = foldMap assetAmountValue mussLockedValue
        }

assetAmountValue :: MuesliSwapAssetAmount -> C.Value
assetAmountValue MuesliSwapAssetAmount{musaAssetId, musaAmount = C.Quantity quantity} =
    case musaAssetId of
        C.AdaAssetId -> C.lovelaceToValue (fromInteger quantity)
        _ -> fromList [(musaAssetId, C.Quantity quantity)]

scriptDataHashFromBytes :: PlutusTx.BuiltinByteString -> C.Hash C.ScriptData
scriptDataHashFromBytes rawBytes =
    either (error . show) id $
        C.deserialiseFromRawBytes (C.AsHash C.AsScriptData) (PlutusTx.fromBuiltin rawBytes)
