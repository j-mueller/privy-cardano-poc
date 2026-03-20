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
import Data.Tagged (Tagged (..))
import Data.Text qualified as Text
import Network.HTTP.Types.Status (status404)
import Network.Wai (pathInfo, rawPathInfo, responseLBS)
import Network.Wai.Handler.Warp qualified as Warp
import Network.Wai.Middleware.Cors (
    CorsResourcePolicy (..),
    cors,
    simpleCorsResourcePolicy,
 )
import Options.Applicative qualified as OA
import Privy.API (APIInEra, APIWithStaticInEra)
import Privy.API.NetworkId qualified as NetworkId
import Privy.API.PrivyPublicKey (
    AsPrivyPublicKeyError (..),
    PrivyPublicKeyError,
 )
import Privy.API.RawSign (
    AsRawSignError (..),
    RawSignError,
 )
import Privy.API.RawSign qualified as RawSign
import Privy.API.SendFunds qualified as SendFunds
import Privy.API.Tx (AsSubmitTxError (..), SubmitTxError)
import Privy.API.Tx qualified as Tx
import Privy.API.Wallet qualified as Wallet
import Servant.API (NoContent (..), Raw, (:<|>) (..))
import Servant.Server (
    Handler (..),
    Server,
    ServerError,
    ServerT,
    err400,
    err500,
    errBody,
    hoistServer,
    serve,
 )
import Servant.Server.StaticFiles (serveDirectoryWebApp)
import System.Environment (lookupEnv)
import System.Exit (die)

data CliOptions
    = CliOptions
    { coPort :: Int
    , coFrontendDir :: Maybe FilePath
    }

data AppError era
    = AppBlockfrostError BlockfrostError
    | AppPrivyPublicKeyError PrivyPublicKeyError
    | AppRawSignError RawSignError
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

instance AsRawSignError (AppError era) where
    _RawSignError = _AppRawSignError

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
    CliOptions{coPort, coFrontendDir} <- parseCliOptions
    project <- getBlockfrostProject
    let apiServer = hoistServer (Proxy @APIInEra) (runApp project) server
    Warp.run coPort $
        cors (const $ Just corsPolicy) $
            serve (Proxy @APIWithStaticInEra) $
                apiServer :<|> staticServer coFrontendDir

server :: ServerT APIInEra AppM
server =
    pure NoContent
        :<|> NetworkId.serve @C.ConwayEra
        :<|> RawSign.serve
        :<|> SendFunds.serve @C.ConwayEra
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

staticServer :: Maybe FilePath -> Server Raw
staticServer = \case
    Nothing ->
        Tagged $
            \_ respond ->
                respond $
                    responseLBS
                        status404
                        [("Content-Type", "text/plain; charset=utf-8")]
                        "Static file serving is disabled."
    Just frontendDir ->
        let staticApp = unTagged (serveDirectoryWebApp frontendDir)
         in Tagged $ \request respond ->
                let request' =
                        if rawPathInfo request == "/"
                            then
                                request
                                    { rawPathInfo = "/index.html"
                                    , pathInfo = ["index.html"]
                                    }
                            else request
                 in staticApp request' respond

parseCliOptions :: IO CliOptions
parseCliOptions =
    OA.execParser $
        OA.info
            (cliOptionsParser OA.<**> OA.helper)
            ( OA.fullDesc
                <> OA.progDesc "Run the privy-cardano API server"
            )

cliOptionsParser :: OA.Parser CliOptions
cliOptionsParser =
    CliOptions
        <$> OA.option
            OA.auto
            ( OA.long "port"
                <> OA.metavar "PORT"
                <> OA.value 8080
                <> OA.showDefault
                <> OA.help "Port to listen on"
            )
        <*> OA.optional
            ( OA.strOption
                ( OA.long "frontend-dir"
                    <> OA.metavar "DIR"
                    <> OA.help "Directory containing static frontend files"
                )
            )

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
    AppRawSignError err ->
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
