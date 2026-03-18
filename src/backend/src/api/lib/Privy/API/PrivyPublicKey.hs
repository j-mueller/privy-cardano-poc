{-# LANGUAGE OverloadedStrings #-}

-- | API Types
module Privy.API.PrivyPublicKey (
    PrivyPublicKey (..),
) where

import Control.Lens ((&), (?~))
import Data.Aeson.TypeScript.TH (TypeScript (..))
import Data.OpenApi.Internal (NamedSchema (..), OpenApiType (OpenApiString))
import Data.OpenApi.Lens qualified as L
import Data.OpenApi.ParamSchema (ToParamSchema (..))
import Data.OpenApi.Schema (ToSchema (..))
import Data.Proxy (Proxy (..))
import Data.Text (Text)
import Servant.API (FromHttpApiData (..), ToHttpApiData (..))

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
