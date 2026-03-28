{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Privy.Orphans () where

import Cardano.Api qualified as C
import Cardano.Protocol.JSON ()
import Control.Lens ((&), (?~))
import Data.Aeson.TypeScript.TH (TypeScript (..))
import Data.OpenApi.Internal (NamedSchema (..), OpenApiType (OpenApiString))
import Data.OpenApi.Lens qualified as L
import Data.OpenApi.Schema (ToSchema (..))
import Servant.API.ContentTypes (NoContent)

instance TypeScript NoContent where
    getTypeScriptType _ = "{}"

instance TypeScript C.TxId where
    getTypeScriptType _ = "string"

instance ToSchema C.TxId where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "TxId") $
                mempty
                    & L.type_ ?~ OpenApiString
                    & L.description ?~ "Hex-encoded Cardano transaction ID"
