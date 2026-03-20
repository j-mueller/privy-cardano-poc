{-# LANGUAGE TemplateHaskell #-}

module Privy.API.NetworkId (
    API,
    NetworkIdKind (..),
    NetworkIdResponse (..),
    serve,
) where

import Cardano.Api qualified as C
import Convex.Class (MonadBlockchain (queryNetworkId))
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import Data.Word (Word32)
import GHC.Generics (Generic)
import Servant.API (Get, JSON, type (:>))
import Servant.Server (ServerT)

data NetworkIdKind
    = NetworkIdPreprod
    | NetworkIdPreview
    | NetworkIdMainnet
    | NetworkIdCustom
    deriving stock (Eq, Show, Generic)

networkIdKindOptions :: Aeson.Options
networkIdKindOptions =
    Aeson.defaultOptions
        { Aeson.constructorTagModifier = Aeson.camelTo2 '_' . drop 9
        }

instance ToJSON NetworkIdKind where
    toJSON = Aeson.genericToJSON networkIdKindOptions
    toEncoding = Aeson.genericToEncoding networkIdKindOptions

instance FromJSON NetworkIdKind where
    parseJSON = Aeson.genericParseJSON networkIdKindOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.constructorTagModifier = Aeson.camelTo2 '_' . drop 9}) ''NetworkIdKind)

instance Schema.ToSchema NetworkIdKind where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions networkIdKindOptions)

data NetworkIdResponse
    = NetworkIdResponse
    { nirNetworkId :: NetworkIdKind
    , nirNetworkMagic :: Maybe Word32
    }
    deriving stock (Eq, Show, Generic)

networkIdResponseOptions :: Aeson.Options
networkIdResponseOptions =
    Aeson.defaultOptions
        { Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3
        }

instance ToJSON NetworkIdResponse where
    toJSON = Aeson.genericToJSON networkIdResponseOptions
    toEncoding = Aeson.genericToEncoding networkIdResponseOptions

instance FromJSON NetworkIdResponse where
    parseJSON = Aeson.genericParseJSON networkIdResponseOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 3}) ''NetworkIdResponse)

instance Schema.ToSchema NetworkIdResponse where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions networkIdResponseOptions)

type API era = "network_id" :> Get '[JSON] NetworkIdResponse

serve :: forall era m. (MonadBlockchain era m) => ServerT (API era) m
serve = getNetworkId

toNetworkIdResponse :: C.NetworkId -> NetworkIdResponse
toNetworkIdResponse = \case
    C.Mainnet ->
        NetworkIdResponse
            { nirNetworkId = NetworkIdMainnet
            , nirNetworkMagic = Nothing
            }
    C.Testnet (C.NetworkMagic magic) ->
        NetworkIdResponse
            { nirNetworkId = case magic of
                1 -> NetworkIdPreprod
                2 -> NetworkIdPreview
                _ -> NetworkIdCustom
            , nirNetworkMagic = Just magic
            }

getNetworkId :: forall era m. (MonadBlockchain era m) => m NetworkIdResponse
getNetworkId = toNetworkIdResponse <$> queryNetworkId
