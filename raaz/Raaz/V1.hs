{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- | Version 1 of the interface.
module Raaz.V1 ( Digest
               , module Raaz.Blake2b
               ) where

import Raaz.Primitive.Blake2.Internal  ( BLAKE2b )
import Raaz.Blake2b

-- | The message digest.
type Digest = BLAKE2b
