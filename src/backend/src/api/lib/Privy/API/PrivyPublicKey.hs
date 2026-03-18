{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | API Types
module Privy.API.PrivyPublicKey (
    PrivyPublicKey (..),
    PrivyPublicKeyError (..),
    AsPrivyPublicKeyError (..),
    toPublicKey,
    toPublicKeyHash,
    toCardanoAddress,
) where

import Cardano.Api qualified as C
import Control.Lens (makeClassyPrisms, (&), (?~))
import Control.Lens qualified as L
import Control.Monad.Except (MonadError (..), liftEither)
import Convex.Class (MonadBlockchain (queryNetworkId))
import Data.Aeson.TypeScript.TH (TypeScript (..))
import Data.Bifunctor (Bifunctor (..))
import Data.OpenApi.Internal (
    NamedSchema (..),
    OpenApiType (OpenApiString),
 )
import Data.OpenApi.Lens qualified as L
import Data.OpenApi.ParamSchema (ToParamSchema (..))
import Data.OpenApi.Schema (ToSchema (..))
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Enc
import Servant.API (
    FromHttpApiData (..),
    ToHttpApiData (..),
 )

newtype PrivyPublicKey = PrivyPublicKey Text
    deriving stock (Eq, Show)

instance TypeScript PrivyPublicKey where
    getTypeScriptType _ = "string"

instance ToParamSchema PrivyPublicKey where
    toParamSchema _ =
        mempty
            & L.type_ ?~ OpenApiString
            & L.description ?~ "Privy wallet public key"

instance ToSchema PrivyPublicKey where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "PrivyPublicKey") $
                toParamSchema (undefined :: Proxy PrivyPublicKey)

instance FromHttpApiData PrivyPublicKey where
    parseUrlPiece = Right . PrivyPublicKey

instance ToHttpApiData PrivyPublicKey where
    toUrlPiece (PrivyPublicKey publicKey) = publicKey

-- | Conversion failures
data PrivyPublicKeyError
    = PrivyPublicKeyConversionFailed C.RawBytesHexError
    deriving (Show)

makeClassyPrisms ''PrivyPublicKeyError

toPublicKey :: (MonadError err m, AsPrivyPublicKeyError err) => PrivyPublicKey -> m (C.VerificationKey C.PaymentKey)
toPublicKey (PrivyPublicKey publicKeyHash) =
    liftEither $
        first (L.review _PrivyPublicKeyConversionFailed) $
            (C.deserialiseFromRawBytesHex (Enc.encodeUtf8 publicKeyHash) :: Either C.RawBytesHexError (C.VerificationKey C.PaymentKey))

toPublicKeyHash :: (MonadError err m, AsPrivyPublicKeyError err) => PrivyPublicKey -> m (C.Hash C.PaymentKey)
toPublicKeyHash =
    fmap C.verificationKeyHash . toPublicKey

toCardanoAddress ::
    ( MonadBlockchain era m
    , MonadError err m
    , AsPrivyPublicKeyError err
    ) =>
    PrivyPublicKey ->
    m (C.Address C.ShelleyAddr)
toCardanoAddress publicKey = do
    pkh <- toPublicKeyHash publicKey
    networkId <- queryNetworkId
    pure $ C.makeShelleyAddress networkId (C.PaymentCredentialByKey pkh) C.NoStakeAddress
