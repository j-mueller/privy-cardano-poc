{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

-- | Wallet API
module Privy.API.Wallet (
    API,
    WalletInfo (..),
    serve,
) where

import Cardano.Api qualified as C
import Control.Monad.Except (MonadError)
import Convex.Class (MonadBlockchain, MonadUtxoQuery, utxosByPaymentCredential)
import Convex.Utxos (totalBalance)
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import GHC.Generics (Generic)
import GHC.IsList (toList)
import Privy.API.PrivyPublicKey (AsPrivyPublicKeyError, PrivyPublicKey, toCardanoAddress, toPublicKeyHash)
import Privy.API.SerialiseAddress (SerialiseAddress (..))
import Privy.Orphans ()
import Servant.API (Capture, Get, JSON, type (:>))
import Servant.Server (ServerT)

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

type API era =
    "wallet"
        :> Capture "public_key" PrivyPublicKey
        :> Get '[JSON] WalletInfo

serve ::
    forall era err m.
    ( MonadBlockchain era m
    , MonadUtxoQuery m
    , MonadError err m
    , AsPrivyPublicKeyError err
    ) =>
    ServerT (API era) m
serve = getWalletInfo

getWalletInfo ::
    forall era err m.
    ( MonadBlockchain era m
    , MonadUtxoQuery m
    , MonadError err m
    , AsPrivyPublicKeyError err
    ) =>
    PrivyPublicKey ->
    m WalletInfo
getWalletInfo publicKey = do
    pkh <- toPublicKeyHash publicKey
    address <- toCardanoAddress publicKey
    let paymentCredential = C.PaymentCredentialByKey pkh
    balance <-
        toList . totalBalance
            <$> utxosByPaymentCredential paymentCredential
    pure
        WalletInfo
            { wiAddress = SerialiseAddress address
            , wiBalance = balance
            }
