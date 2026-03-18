{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Privy.API.Tx (
    ApiTx,
    ApiTxDummy,
    PrivySignature (..),
    KeyWitness (..),
    SubmitTxArgs (..),
    SubmitTxError (..),
    AsSubmitTxError (..),
    txApiTypeScriptExtraTypes,
    apiTx,
    submitTx,
    API,
    serve,
) where

import Cardano.Api qualified as C
import Cardano.Api.Ledger qualified as ApiLedger
import Cardano.Crypto.DSIGN.Class qualified as Crypto
import Cardano.Ledger.Core qualified as LedgerCore
import Cardano.Ledger.Hashes qualified as LedgerHashes
import Cardano.Ledger.Keys qualified as LedgerKeys
import Cardano.Ledger.Keys.WitVKey qualified as LedgerWit
import Control.Lens (
    makeClassyPrisms,
    review,
    (&),
    (?~),
 )
import Control.Monad.Except (MonadError, liftEither)
import Convex.Class (MonadBlockchain)
import Convex.Class qualified as Chain
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (
    TSType (..),
    TypeScript (..),
    deriveTypeScript,
 )
import Data.Bifunctor (first)
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
import Privy.API.PrivyPublicKey (
    AsPrivyPublicKeyError,
    PrivyPublicKey,
    toPublicKey,
 )
import Privy.API.TextEnvelope (
    TextEnvelopeJSON (..),
    TextEnvelopeJsonDummy,
 )
import Servant.API (JSON, Post, ReqBody, type (:>))
import Servant.Server (ServerT)

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

newtype PrivySignature = PrivySignature Text
    deriving stock (Eq, Show)

instance ToJSON PrivySignature where
    toJSON (PrivySignature signature) = Aeson.String signature

instance FromJSON PrivySignature where
    parseJSON =
        Aeson.withText "PrivySignature" $
            pure . PrivySignature

instance TypeScript PrivySignature where
    getTypeScriptType _ = "string"

instance Schema.ToSchema PrivySignature where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "PrivySignature") $
                mempty
                    & L.type_ ?~ OpenApiString
                    & L.description ?~ "Hex-encoded Ed25519 signature returned by Privy raw_sign"

data KeyWitness
    = KeyWitness
    { kwPublicKey :: PrivyPublicKey
    , kwSignature :: PrivySignature
    }
    deriving stock (Eq, Show, Generic)

keyWitnessOptions :: Aeson.Options
keyWitnessOptions =
    Aeson.defaultOptions
        { Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 2
        }

instance ToJSON KeyWitness where
    toJSON = Aeson.genericToJSON keyWitnessOptions
    toEncoding = Aeson.genericToEncoding keyWitnessOptions

instance FromJSON KeyWitness where
    parseJSON = Aeson.genericParseJSON keyWitnessOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 2}) ''KeyWitness)

instance Schema.ToSchema KeyWitness where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions keyWitnessOptions)

data SubmitTxArgsDummy
    = SubmitTxArgsDummy
    { stadTransaction :: TextEnvelopeJsonDummy
    , stadWitnesses :: [KeyWitness]
    }
    deriving stock (Generic)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 4}) ''SubmitTxArgsDummy)

data SubmitTxArgs era
    = SubmitTxArgs
    { staTransaction :: TextEnvelopeJSON (C.Tx era)
    , staWitnesses :: [KeyWitness]
    }
    deriving stock (Eq, Show, Generic)

submitTxArgsOptions :: Aeson.Options
submitTxArgsOptions =
    Aeson.defaultOptions
        { Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3
        }

instance (C.IsShelleyBasedEra era) => ToJSON (SubmitTxArgs era) where
    toJSON = Aeson.genericToJSON submitTxArgsOptions
    toEncoding = Aeson.genericToEncoding submitTxArgsOptions

instance (C.IsShelleyBasedEra era) => FromJSON (SubmitTxArgs era) where
    parseJSON = Aeson.genericParseJSON submitTxArgsOptions

instance (Typeable era) => TypeScript (SubmitTxArgs era) where
    getTypeScriptType _ = getTypeScriptType (Proxy @SubmitTxArgsDummy)

instance (C.IsShelleyBasedEra era) => Schema.ToSchema (SubmitTxArgs era) where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions submitTxArgsOptions)

data SubmitTxError
    = SubmitTxWitnessDeserialisationFailed String
    deriving stock (Show)

makeClassyPrisms ''SubmitTxError

txApiTypeScriptExtraTypes :: [TSType]
txApiTypeScriptExtraTypes =
    [ TSType (Proxy @ApiTxDummy)
    , TSType (Proxy @KeyWitness)
    , TSType (Proxy @SubmitTxArgsDummy)
    , TSType (Proxy @TextEnvelopeJsonDummy)
    ]

mkKeyWitness ::
    forall era.
    (C.IsShelleyBasedEra era) =>
    C.VerificationKey C.PaymentKey ->
    PrivySignature ->
    Either String (C.KeyWitness era)
mkKeyWitness paymentVerificationKey (PrivySignature signatureText) = do
    rawSignature <- Base16.decode (Enc.encodeUtf8 signatureText)
    signature <-
        maybe
            (Left "Failed to deserialise Privy signature")
            Right
            (Crypto.rawDeserialiseSigDSIGN rawSignature)
    verificationKey <-
        maybe
            (Left "Failed to deserialise Cardano verification key")
            Right
            (Crypto.rawDeserialiseVerKeyDSIGN (C.serialiseToRawBytes paymentVerificationKey))
    pure $
        C.ShelleyKeyWitness
            C.shelleyBasedEra
            (LedgerWit.WitVKey (LedgerKeys.VKey verificationKey) (Crypto.SignedDSIGN signature))

type API era = "submit_tx" :> ReqBody '[JSON] (SubmitTxArgs era) :> Post '[JSON] C.TxId

serve ::
    forall era err m.
    ( MonadBlockchain era m
    , C.IsShelleyBasedEra era
    , MonadError err m
    , AsPrivyPublicKeyError err
    , AsSubmitTxError err
    , Chain.AsSendTxError err era
    ) =>
    ServerT (API era) m
serve = submitTx

submitTx ::
    forall era err m.
    ( MonadBlockchain era m
    , C.IsShelleyBasedEra era
    , MonadError err m
    , AsPrivyPublicKeyError err
    , AsSubmitTxError err
    , Chain.AsSendTxError err era
    ) =>
    SubmitTxArgs era ->
    m C.TxId
submitTx SubmitTxArgs{staTransaction = TextEnvelopeJSON (C.Tx txBody existingWitnesses), staWitnesses} = do
    witnesses <-
        traverse
            ( \KeyWitness{kwPublicKey, kwSignature} -> do
                paymentVerificationKey <- toPublicKey kwPublicKey
                liftEither $
                    first (review _SubmitTxWitnessDeserialisationFailed) $
                        mkKeyWitness @era paymentVerificationKey kwSignature
            )
            staWitnesses
    Chain.sendTx
        (C.makeSignedTransaction (existingWitnesses <> witnesses) txBody)
        >>= liftEither . first (review Chain._SendTxError)
