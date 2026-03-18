{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Privy.API.TextEnvelope (
    TextEnvelopeJSON (..),
    TextEnvelopeJsonDummy,
) where

import Cardano.Api qualified as C
import Control.Lens ((&), (.~), (?~))
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (TypeScript (..), deriveTypeScript)
import Data.OpenApi (
    NamedSchema (..),
    OpenApiType (OpenApiObject),
    Referenced (Inline),
    ToSchema (..),
 )
import Data.OpenApi.Internal (OpenApiType (OpenApiString))
import Data.OpenApi.Lens qualified as L
import Data.Proxy (Proxy (..))
import Data.Typeable (Typeable)
import GHC.Generics (Generic)

data TextEnvelopeJsonDummy
    = TextEnvelopeJsonDummy
    { tejcborHex :: String
    , tejdescription :: String
    , tejtype :: String
    }
    deriving stock (Generic)

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = drop 3}) ''TextEnvelopeJsonDummy)

instance (Typeable a) => TypeScript (TextEnvelopeJSON a) where
    getTypeScriptType _ = getTypeScriptType (Proxy @TextEnvelopeJsonDummy)

newtype TextEnvelopeJSON a = TextEnvelopeJSON {unTextEnvelopeJSON :: a}
    deriving newtype (Eq, Show)

instance (C.HasTextEnvelope a) => ToJSON (TextEnvelopeJSON a) where
    toJSON = toJSON . C.serialiseToTextEnvelope Nothing . unTextEnvelopeJSON

instance (C.HasTextEnvelope a) => FromJSON (TextEnvelopeJSON a) where
    parseJSON val =
        parseJSON val
            >>= either (fail . show) (pure . TextEnvelopeJSON) . C.deserialiseFromTextEnvelope

instance (C.HasTextEnvelope a) => ToSchema (TextEnvelopeJSON a) where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "TextEnvelopeJSON") $
                mempty
                    & L.type_ ?~ OpenApiObject
                    & L.description ?~ "Text envelope"
                    & L.properties
                        .~ [ ("cborHex", Inline $ mempty & L.type_ ?~ OpenApiString & L.description ?~ "The CBOR-serialised value, base-16 encoded")
                           , ("description", Inline $ mempty & L.type_ ?~ OpenApiString & L.description ?~ "Description of the serialised value")
                           , ("type", Inline $ mempty & L.type_ ?~ OpenApiString & L.description ?~ "Type of the serialised value")
                           ]
