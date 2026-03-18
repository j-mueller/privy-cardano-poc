{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}

-- | Wallet API
module Privy.API.Wallet (
    API,
    WalletInfo (..),
) where

import Cardano.Api qualified as C
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import GHC.Generics (Generic)
import Privy.API.PrivyPublicKey (PrivyPublicKey)
import Privy.API.SerialiseAddress (SerialiseAddress)
import Privy.Orphans ()
import Servant.API (
    Capture,
    Get,
    JSON,
    type (:>),
 )

-- | State of the address
data WalletInfo
    = WalletInfo
    { wiAddress :: SerialiseAddress (C.Address C.ShelleyAddr)
    -- ^ Wallet cardano address
    , wiBalance :: [(C.AssetId, C.Quantity)]
    }
    deriving stock (Eq, Show, Generic)

walletInfoOptions :: Aeson.Options
walletInfoOptions =
    Aeson.defaultOptions
        { Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 2
        }

instance ToJSON WalletInfo where
    toJSON = Aeson.genericToJSON walletInfoOptions
    toEncoding = Aeson.genericToEncoding walletInfoOptions

instance FromJSON WalletInfo where
    parseJSON = Aeson.genericParseJSON walletInfoOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 2}) ''WalletInfo)

instance Schema.ToSchema WalletInfo where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions walletInfoOptions)

type API = "wallet" :> Capture "public_key" PrivyPublicKey :> Get '[JSON] WalletInfo
