{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Privy.API.SendFunds (
    API,
    AssetEntry (..),
    SendFundsRequest (..),
    SendFundsError (..),
    AsSendFundsError (..),
    serve,
    paymentCredentialFromAddress,
    sendFunds,
) where

import Cardano.Api qualified as C hiding (queryProtocolParameters)
import Control.Lens (makeClassyPrisms)
import Control.Monad.Error.Lens (throwing_)
import Control.Monad.Except (MonadError)
import Convex.BuildTx qualified as BuildTx
import Convex.CardanoApi.Lenses (emptyTxOut)
import Convex.Class (MonadBlockchain, MonadUtxoQuery)
import Convex.Class qualified as Chain
import Convex.CoinSelection qualified as CoinSelection
import Data.Aeson (FromJSON (..), ToJSON (..))
import Data.Aeson qualified as Aeson
import Data.Aeson.TypeScript.TH (deriveTypeScript)
import Data.OpenApi.Schema qualified as Schema
import Data.OpenApi.SchemaOptions qualified as SchemaOptions
import Data.Set qualified as Set
import GHC.Exts (fromList)
import GHC.Generics (Generic)
import Privy.API.SerialiseAddress (SerialiseAddress (..))
import Privy.API.SubmitTx (ApiTx, apiTx)
import Privy.Orphans ()
import Servant.API (JSON, Post, ReqBody, type (:>))
import Servant.Server (ServerT)

data SendFundsError
    = NoSenders
    deriving stock (Show)

makeClassyPrisms ''SendFundsError

data AssetEntry
    = AssetEntry
    { aeAsset :: C.AssetId
    , aeAmount :: C.Quantity
    }
    deriving stock (Eq, Show, Generic)

assetEntryOptions :: Aeson.Options
assetEntryOptions =
    Aeson.defaultOptions
        { Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 2
        }

instance ToJSON AssetEntry where
    toJSON = Aeson.genericToJSON assetEntryOptions
    toEncoding = Aeson.genericToEncoding assetEntryOptions

instance FromJSON AssetEntry where
    parseJSON = Aeson.genericParseJSON assetEntryOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 2}) ''AssetEntry)

instance Schema.ToSchema AssetEntry where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions assetEntryOptions)

data SendFundsRequest
    = SendFundsRequest
    { sfSenders :: [SerialiseAddress (C.Address C.ShelleyAddr)]
    , sfReceiver :: SerialiseAddress (C.Address C.ShelleyAddr)
    , sfAssets :: [AssetEntry]
    }
    deriving stock (Eq, Show, Generic)

sendFundsRequestOptions :: Aeson.Options
sendFundsRequestOptions =
    Aeson.defaultOptions
        { Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 2
        }

requestValue :: SendFundsRequest -> C.Value
requestValue =
    fromList . fmap (\AssetEntry{aeAsset, aeAmount} -> (aeAsset, aeAmount)) . sfAssets

instance ToJSON SendFundsRequest where
    toJSON = Aeson.genericToJSON sendFundsRequestOptions
    toEncoding = Aeson.genericToEncoding sendFundsRequestOptions

instance FromJSON SendFundsRequest where
    parseJSON = Aeson.genericParseJSON sendFundsRequestOptions

$(deriveTypeScript (Aeson.defaultOptions{Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop 2}) ''SendFundsRequest)

instance Schema.ToSchema SendFundsRequest where
    declareNamedSchema = Schema.genericDeclareNamedSchema (SchemaOptions.fromAesonOptions sendFundsRequestOptions)

type API era = "send_funds" :> ReqBody '[JSON] SendFundsRequest :> Post '[JSON] (ApiTx era)

serve ::
    forall era err m.
    ( MonadBlockchain era m
    , MonadError err m
    , MonadUtxoQuery m
    , C.IsBabbageBasedEra era
    , AsSendFundsError err
    , CoinSelection.AsBalancingError err era
    , CoinSelection.AsCoinSelectionError err
    ) =>
    ServerT (API era) m
serve = sendFunds

sendFunds ::
    forall era err m.
    ( MonadBlockchain era m
    , MonadError err m
    , MonadUtxoQuery m
    , C.IsBabbageBasedEra era
    , AsSendFundsError err
    , CoinSelection.AsBalancingError err era
    , CoinSelection.AsCoinSelectionError err
    ) =>
    SendFundsRequest ->
    m (ApiTx era)
sendFunds request@SendFundsRequest{sfSenders, sfReceiver} =
    case fmap unSerialiseAddress sfSenders of
        [] -> throwing_ _NoSenders
        senders@(sender : _) -> do
            let val = requestValue request
            params <- Chain.queryProtocolParameters
            senderUtxos <-
                Chain.utxosByPaymentCredentials $
                    Set.fromList $
                        paymentCredentialFromAddress <$> senders
            (_, txBuilder) <- BuildTx.runBuildTxT $ do
                BuildTx.payToAddress
                    (C.AddressInEra (C.ShelleyAddressInEra C.shelleyBasedEra) (unSerialiseAddress sfReceiver))
                    val
                BuildTx.setMinAdaDepositAll params
            let returnOutput =
                    emptyTxOut $
                        C.AddressInEra (C.ShelleyAddressInEra C.shelleyBasedEra) sender
            (balancedTxBody, _) <-
                CoinSelection.balanceTx
                    mempty
                    returnOutput
                    senderUtxos
                    txBuilder
                    CoinSelection.TrailingChange
            pure $
                apiTx $
                    CoinSelection.signBalancedTxBody [] balancedTxBody

paymentCredentialFromAddress :: C.Address C.ShelleyAddr -> C.PaymentCredential
paymentCredentialFromAddress = \case
    C.ShelleyAddress _ credential _ -> C.fromShelleyPaymentCredential credential
