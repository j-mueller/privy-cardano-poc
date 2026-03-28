{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE UndecidableInstances #-}

module Privy.API.SerialisedPlutusDatum (
    SerialisedPlutusDatum (..),
) where

import Cardano.Api qualified as C
import Control.Lens ((&), (?~))
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (TypeScript (..))
import Data.ByteString.Base16 qualified as Base16
import Data.OpenApi (NamedSchema (..))
import Data.OpenApi.Internal (OpenApiType (OpenApiString))
import Data.OpenApi.Lens qualified as L
import Data.OpenApi.Schema qualified as Schema
import Data.Text.Encoding qualified as Enc

newtype SerialisedPlutusDatum = SerialisedPlutusDatum {unSerialisedPlutusDatum :: C.ScriptData}
    deriving stock (Eq, Show)

instance ToJSON SerialisedPlutusDatum where
    toJSON (SerialisedPlutusDatum datum) =
        Aeson.String $
            Enc.decodeUtf8 $
                Base16.encode $
                    C.serialiseToCBOR datum

instance FromJSON SerialisedPlutusDatum where
    parseJSON =
        Aeson.withText "SerialisedPlutusDatum" $ \text -> do
            rawBytes <-
                either (fail . show) pure $
                    Base16.decode (Enc.encodeUtf8 text)
            datum <-
                either (fail . show) pure $
                    C.deserialiseFromCBOR C.AsScriptData rawBytes
            pure (SerialisedPlutusDatum datum)

instance TypeScript SerialisedPlutusDatum where
    getTypeScriptType _ = "string"

instance Schema.ToSchema SerialisedPlutusDatum where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "SerialisedPlutusDatum") $
                mempty
                    & L.type_ ?~ OpenApiString
                    & L.description ?~ "Hex-encoded CBOR serialised Plutus datum"
