{-|

Generic cryptographic block primtives and their implementations. This
module exposes low-level generic code used in the raaz system. Most
likely, one would not need to stoop so low and it might be better to
use a more high level interface.

-}

{-# LANGUAGE TypeFamilies                #-}
{-# LANGUAGE FlexibleContexts            #-}
{-# LANGUAGE DataKinds                   #-}

module Raaz.Core.Primitive
       ( -- * Cryptographic Primtives
         Primitive(..)
       ) where

import GHC.TypeLits

----------------------- A primitive ------------------------------------


-- | The type class that captures an abstract block cryptographic
-- primitive.
class KnownNat (BlockSize p) => Primitive p where

  -- | Bulk cryptographic primitives like hashes, ciphers etc often
  -- acts on blocks of data. The size of the block is captured by the
  -- associated type `BlockSize`.
  type BlockSize p :: Nat

  -- | The key associated with primitive. In the setting of the raaz
  -- library keys are "inputs" that are required to start processing.
  -- Often primitives like ciphers have a /secret key/ together with
  -- an additional nounce/IV. This type denotes not just the secret
  -- key par but the nounce too.
  --
  -- Primitives like hashes that do not require a key should have this
  -- type defined as `()`.

  type Key p :: *

  -- | Many primitives produce additional message digest after
  -- processing the input, think of cryptographic hashes, AEAD
  -- primitives etc. This associated type captures such additional
  -- data produced by the primitive.
  type Digest p :: *
