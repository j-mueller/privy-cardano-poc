{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Privy.API.Tx (
    ApiTx,
    apiTx,
) where

import Cardano.Api qualified as C
import Cardano.Api.Ledger qualified as ApiLedger
import Cardano.Ledger.Core qualified as LedgerCore
import Cardano.Ledger.Hashes qualified as LedgerHashes
import Control.Lens ((&), (?~))
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (TypeScript (..), deriveTypeScript)
import Data.ByteString.Base16 qualified as Base16
import Data.OpenApi (NamedSchema (..))
import Data.OpenApi.Internal (OpenApiType (OpenApiString))
import Data.OpenApi.Lens qualified as L
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text.Encoding qualified as Enc
import Data.Typeable (Typeable)
import GHC.Generics (Generic)
import Privy.API.TextEnvelope (TextEnvelopeJSON (..), TextEnvelopeJsonDummy)

newtype TxBodyHash = TxBodyHash (ApiLedger.SafeHash LedgerCore.EraIndependentTxBody)
    deriving stock (Eq, Show)

data ApiTx era
    = ApiTx
    { atxTransaction :: TextEnvelopeJSON (C.Tx era) -- Full transaction in Text envelope format
    , atxTxBodyHash :: TxBodyHash
    }
    deriving stock (Eq, Show, Generic)

data ApiTxDummy
    = ApiTxDummy
    { atdTransaction :: TextEnvelopeJsonDummy
    , atdTxBodyHash :: TxBodyHash
    }
    deriving stock (Generic)

txBodyHashToText :: TxBodyHash -> Text
txBodyHashToText (TxBodyHash hash) = C.renderSafeHashAsHex hash

textToTxBodyHash :: Text -> Either String TxBodyHash
textToTxBodyHash text = do
    rawBytes <- Base16.decode (Enc.encodeUtf8 text)
    maybe
        (Left "Failed to deserialise tx body hash")
        (Right . TxBodyHash)
        (ApiLedger.unsafeMakeSafeHash <$> ApiLedger.hashFromBytes rawBytes)

instance ToJSON TxBodyHash where
    toJSON = Aeson.String . txBodyHashToText

instance FromJSON TxBodyHash where
    parseJSON =
        Aeson.withText "TxBodyHash" $
            either fail pure . textToTxBodyHash

instance TypeScript TxBodyHash where
    getTypeScriptType _ = "string"

instance Schema.ToSchema TxBodyHash where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "TxBodyHash") $
                mempty
                    & L.type_ ?~ OpenApiString
                    & L.description ?~ "Hex-encoded Cardano transaction body hash"

apiTxOptions :: Aeson.Options
apiTxOptions =
    Aeson.defaultOptions
        { Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3
        }

instance (C.IsShelleyBasedEra era) => ToJSON (ApiTx era) where
    toJSON = Aeson.genericToJSON apiTxOptions
    toEncoding = Aeson.genericToEncoding apiTxOptions

instance (C.IsShelleyBasedEra era) => FromJSON (ApiTx era) where
    parseJSON = Aeson.genericParseJSON apiTxOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3}) ''ApiTxDummy)

instance (Typeable era) => TypeScript (ApiTx era) where
    getTypeScriptType _ = getTypeScriptType (Proxy @ApiTxDummy)

instance (C.IsShelleyBasedEra era) => Schema.ToSchema (ApiTx era) where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions apiTxOptions)

apiTx :: C.Tx era -> ApiTx era
apiTx tx =
    ApiTx
        { atxTransaction = TextEnvelopeJSON tx
        , atxTxBodyHash =
            TxBodyHash $
                case C.getTxBody tx of
                    C.ShelleyTxBody sbe ledgerTxBody _ _ _ _ ->
                        C.shelleyBasedEraConstraints sbe $
                            LedgerHashes.hashAnnotated ledgerTxBody
        }
