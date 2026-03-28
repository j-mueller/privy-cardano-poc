module Privy.API.Utils (
    jsonOptions,
) where

import Data.Aeson qualified as Aeson

jsonOptions :: Int -> Aeson.Options
jsonOptions dropChars =
    Aeson.defaultOptions
        { Aeson.fieldLabelModifier = Aeson.camelTo2 '_' . drop dropChars
        }
