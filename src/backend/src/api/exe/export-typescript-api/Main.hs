{-# LANGUAGE QuasiQuotes #-}

module Main (
    main,
)
where

import Data.Proxy (Proxy (..))
import Data.String.Interpolate (i)
import Privy.API (APIInEra)
import Privy.API.SubmitTx (txApiTypeScriptExtraTypes)
import Servant.TypeScript (
    defaultServantTypeScriptOptions,
    extraTypes,
    getFunctions,
    writeTypeScriptLibrary',
 )
import System.Environment (getArgs)
import System.Exit (exitFailure)

main :: IO ()
main =
    getArgs >>= \case
        [fp] -> do
            putStrLn $ "Writing typescript API to " <> fp
            let firstLine = [i| /// <reference path="./client.d.ts" /> \n |]
                options =
                    defaultServantTypeScriptOptions
                        { extraTypes = txApiTypeScriptExtraTypes
                        , getFunctions = \fn reqs -> firstLine <> getFunctions defaultServantTypeScriptOptions fn reqs
                        }
            writeTypeScriptLibrary' options (Proxy :: Proxy APIInEra) fp
        _ -> do
            putStrLn "usage: export-typescript-api TYPESCRIPT_API_FILE"
            exitFailure
