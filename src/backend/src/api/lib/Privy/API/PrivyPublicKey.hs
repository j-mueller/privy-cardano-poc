-- | API Types
module Privy.API.PrivyPublicKey(
  PrivyPublicKey(..)
) where

import Data.Text (Text)

newtype PrivyPublicKey = PrivyPublicKey Text