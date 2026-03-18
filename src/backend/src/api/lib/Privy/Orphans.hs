{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Privy.Orphans () where

import Cardano.Api qualified as C
import Control.Lens ((&), (?~))
import Data.Aeson.TypeScript.TH (TypeScript (..))
import Data.OpenApi.Internal (NamedSchema (..), OpenApiType (OpenApiString))
import Data.OpenApi.Lens qualified as L
import Data.OpenApi.Schema (ToSchema (..))
import Servant.API.ContentTypes (NoContent)

instance ToSchema (C.Address C.ShelleyAddr) where
    declareNamedSchema _ =
        pure $
            NamedSchema (Just "Address") $
                mempty
                    & L.type_ ?~ OpenApiString
                    & L.description ?~ "bech32-encoded cardano address"
                    & L.example ?~ "addr_test1qpju2uhn72ur6j5alln6nz7dqcgcjal7xjaw7lwdjdaex4qhr3xpz63fjwvlpsnu8efnhfdja78d3vkv8ks6ac09g3usemu2yl"

instance TypeScript NoContent where
    getTypeScriptType _ = "{}"
