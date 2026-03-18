{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}

module Privy.Cli (
    main,
) where

import Blockfrost.Auth (mkProject)
import Blockfrost.Client.Auth (Project)
import Blockfrost.Client.Types (BlockfrostError)
import Cardano.Api qualified as C
import Control.Lens (makePrisms)
import Control.Monad.Trans.Except (ExceptT (..), runExceptT)
import Convex.Blockfrost (BlockfrostT, evalBlockfrostT)
import Convex.Class qualified as Chain
import Convex.CoinSelection (
    AsBalancingError (..),
    AsCoinSelectionError (..),
    BalancingError,
    CoinSelectionError,
 )
import Data.ByteString.Lazy.Char8 qualified as LBS8
import Data.Proxy (Proxy (..))
import Data.Text qualified as Text
import Network.Wai.Handler.Warp qualified as Warp
import Network.Wai.Middleware.Cors (
    CorsResourcePolicy (..),
    cors,
    simpleCorsResourcePolicy,
 )
import Privy.API (APIInEra)
import Privy.API.PrivyPublicKey (
    AsPrivyPublicKeyError (..),
    PrivyPublicKeyError,
 )
import Privy.API.SendFunds qualified as SendFunds
import Privy.API.Tx (AsSubmitTxError (..), SubmitTxError)
import Privy.API.Tx qualified as Tx
import Privy.API.Wallet qualified as Wallet
import Servant.API (NoContent (..), (:<|>) (..))
import Servant.Server (
    Handler (..),
    ServerError,
    ServerT,
    err400,
    err500,
    errBody,
    hoistServer,
    serve,
 )
import System.Environment (getArgs, lookupEnv)
import System.Exit (die)
import Text.Read (readMaybe)

data AppError era
    = AppBlockfrostError BlockfrostError
    | AppPrivyPublicKeyError PrivyPublicKeyError
    | AppSendFundsError SendFunds.SendFundsError
    | AppCoinSelectionError CoinSelectionError
    | AppBalancingError (BalancingError era)
    | AppSubmitTxError SubmitTxError
    | AppSendTxError (Chain.SendTxError era)
    deriving stock (Show)

makePrisms ''AppError

instance SendFunds.AsSendFundsError (AppError era) where
    _SendFundsError = _AppSendFundsError

instance AsPrivyPublicKeyError (AppError era) where
    _PrivyPublicKeyError = _AppPrivyPublicKeyError

instance AsCoinSelectionError (AppError era) where
    _CoinSelectionError = _AppCoinSelectionError

instance AsBalancingError (AppError era) era where
    __BalancingError = _AppBalancingError

instance AsSubmitTxError (AppError era) where
    _SubmitTxError = _AppSubmitTxError

instance Chain.AsSendTxError (AppError era) era where
    _SendTxError = _AppSendTxError

type AppM = ExceptT (AppError C.ConwayEra) (BlockfrostT IO)

corsPolicy :: CorsResourcePolicy
corsPolicy =
    simpleCorsResourcePolicy
        { corsMethods = ["GET", "POST", "OPTIONS", "DELETE"]
        , corsRequestHeaders = ["Content-Type", "Authorization", "X-Cardano-Wallet", "X-Request-Id"]
        , corsMaxAge = Nothing
        }

main :: IO ()
main = do
    port <- getPort
    project <- getBlockfrostProject
    Warp.run port $
        cors (const $ Just corsPolicy) $
            serve (Proxy @APIInEra) $
                hoistServer (Proxy @APIInEra) (runApp project) server

server :: ServerT APIInEra AppM
server =
    pure NoContent
        :<|> Wallet.serve @C.ConwayEra
        :<|> Tx.serve @C.ConwayEra

runApp :: Project -> AppM a -> Handler a
runApp project action =
    Handler . ExceptT $ do
        result <- evalBlockfrostT project (runExceptT action)
        pure $ case result of
            Left err -> Left (appErrorToServerError (AppBlockfrostError err))
            Right (Left err) -> Left (appErrorToServerError err)
            Right (Right value) -> Right value

getPort :: IO Int
getPort =
    getArgs >>= \case
        [] -> pure 8080
        [portArg] ->
            maybe
                (die $ "Invalid port: " <> portArg)
                pure
                (readMaybe portArg)
        _ -> die "Usage: privy-cardano-api [port]"

getBlockfrostProject :: IO Project
getBlockfrostProject = do
    lookupEnv "PRIVY_CARDANO_BLOCKFROST_PROJECT" >>= \case
        Nothing ->
            die "Missing PRIVY_CARDANO_BLOCKFROST_PROJECT"
        Just project ->
            pure $ mkProject (Text.pack project)

appErrorToServerError :: AppError C.ConwayEra -> ServerError
appErrorToServerError = \case
    AppBlockfrostError err ->
        err500
            { errBody = LBS8.pack (show err)
            }
    AppPrivyPublicKeyError err ->
        err400
            { errBody = LBS8.pack (show err)
            }
    AppSendFundsError err ->
        err400
            { errBody = LBS8.pack (show err)
            }
    AppCoinSelectionError err ->
        err400
            { errBody = LBS8.pack (show err)
            }
    AppBalancingError err ->
        err400
            { errBody = LBS8.pack (show err)
            }
    AppSubmitTxError err ->
        err400
            { errBody = LBS8.pack (show err)
            }
    AppSendTxError err ->
        err400
            { errBody = LBS8.pack (show err)
            }
