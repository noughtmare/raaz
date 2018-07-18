-- | The module exposes the ChaCha20 based PRG.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DataKinds        #-}
module Raaz.Random.ChaCha20PRG
       ( reseedMT, fillRandomBytesMT, RandomState
       ) where

import Control.Applicative
import Control.Monad
import Control.Monad.Reader   ( ask, withReaderT )
import Data.Proxy             ( Proxy(..)        )
import Foreign.Ptr            ( castPtr          )
import Prelude

import Raaz.Core
import Raaz.Primitive.ChaCha20.Internal
import Raaz.Cipher.ChaCha20.Util as U
import Raaz.Entropy


-- | The maximum value of counter before reseeding from entropy
-- source. Currently set to 1024 * 1024 * 1024. Which will generate
-- 64GB before reseeding.
--
-- The reason behind the choice of the reseeding limit is the
-- following The counter is a 32-bit quantity. Which means that one
-- can generate 2^32 blocks of data before the counter roles over and
-- starts repeating. We have choosen a conservative 2^30 blocks
-- here. Note that the roll over of the counter is not really relevant
-- here as we updated the key,iv for every few chunks of the chacha20
-- key stream (note the fast key erasure technique
-- <https://blog.cr.yp.to/20170723-random.html>) but still this gives
-- some justification for the choice of the parameter.
maxCounterVal :: Counter
maxCounterVal = 1024 * 1024 * 1024


-- | The number of blocks of ChaCha20 that is generated in one go
-- encoded as a type level nat.
type RandomBufferSize = 16

-- | The buffer to store randomness.
type RandomBuffer     = U.Buffer RandomBufferSize



-- | Memory for storing the csprg state.
data RandomState = RandomState { chacha20State  :: U.Internals
                               , auxBuffer      :: RandomBuffer
                               , remainingBytes :: MemoryCell (BYTES Int)
                               }

-- | Apply chacha20 on the contents of the random buffer.
chacha20Random :: MT RandomState ()
chacha20Random = askBuffer >>= withReaderT chacha20State . U.processBuffer
  where askBuffer = auxBuffer <$> ask

instance Memory RandomState where
  memoryAlloc     = RandomState <$> memoryAlloc <*> memoryAlloc <*> memoryAlloc
  unsafeToPointer = unsafeToPointer  . chacha20State

-------------------------- Some helper functions on random state -------------------

-- | Run an action on the auxilary buffer.
withAuxBuffer :: (BufferPtr -> MT RandomState a) -> MT RandomState a
withAuxBuffer action = askBufferPointer >>= action
  where askBufferPointer = getBufferPointer . auxBuffer <$> ask
-- | Get the number of bytes in the buffer.
getRemainingBytes :: MT RandomState (BYTES Int)
getRemainingBytes = withReaderT remainingBytes extract

-- | Set the number of remaining bytes.
setRemainingBytes :: BYTES Int -> MT RandomState ()
setRemainingBytes = withReaderT remainingBytes . initialise

-------------------------------- The PRG operations ---------------------------------------------

-- | The overall idea is to generate a key stream into the auxilary
-- buffer using chacha20 and giving out bytes from this buffer. This
-- operation we call sampling. A portion of the sample is used for
-- resetting the key and iv to make the prg safe against backward
-- prediction, i.e. even if one knows the current seed (i.e. key iv
-- pair) one cannot predict the random values generated before.



-- | This fills in the random block with some new randomness
newSample :: MT RandomState ()
newSample = do
  seedIfReq
  --
  -- Generate key stream
  --
  chacha20Random
  setRemainingBytes $ inBytes $ bufferSize (Proxy :: Proxy RandomBuffer)
  --
  -- Use part of the generated data to re-key the chacha20 cipher
  --
  fillKeyIVWith fillExistingBytes


-- | See the PRG from system entropy.
seed :: MT RandomState ()
seed = do withReaderT (counterCell . chacha20State) $ initialise (0 :: Counter)
          fillKeyIVWith getEntropy

-- | Seed if we have already generated maxCounterVal blocks of random
-- bytes.
seedIfReq :: MT RandomState ()
seedIfReq = do c <- withReaderT (counterCell . chacha20State) extract
               when (c > maxCounterVal) seed

-- | Fill the iv and key from a filling function.
fillKeyIVWith :: (BYTES Int -> Pointer -> MT RandomState a) -- ^ The function used to fill the buffer
              -> MT RandomState ()
fillKeyIVWith filler = let
  keySize = sizeOf (Proxy :: Proxy KEY)
  ivSize  = sizeOf (Proxy :: Proxy IV)
  in do withReaderT (keyCell . chacha20State) getCellPointer >>= void . filler keySize . castPtr
        withReaderT (ivCell  . chacha20State) getCellPointer >>= void . filler ivSize  . castPtr





--------------------------- DANGEROUS CODE ---------------------------------------

-- | Reseed the prg.
reseedMT :: MT RandomState ()
reseedMT = seed >> newSample

-- NONTRIVIALITY: Picking up the newSample is important when we first
-- reseed.

-- | The function to generate random bytes. Fills from existing bytes
-- and continues if not enough bytes are obtained.
fillRandomBytesMT :: LengthUnit l => l -> Pointer -> MT RandomState ()
fillRandomBytesMT l = go (inBytes l)
  where go m ptr
            | m > 0  = do mGot <- fillExistingBytes m ptr   -- Fill from the already generated buffer.
                          when (mGot <= 0) newSample        -- We did not get any so sample.
                          go (m - mGot) $ movePtr ptr mGot  -- Get the remaining.
            | otherwise = return ()   -- Nothing to do


-- | Fill from already existing bytes. Returns the number of bytes
-- filled. Let remaining bytes be r. Then fillExistingBytes will fill
-- min(r,m) bytes into the buffer, and return the number of bytes
-- filled.
fillExistingBytes :: BYTES Int -> Pointer -> MT RandomState (BYTES Int)
fillExistingBytes req ptr = withAuxBuffer $ \ buf -> do
  let sptr = forgetAlignment buf
      in do r <- getRemainingBytes
            let m  = min r req            -- actual bytes filled.
                l  = r - m                -- leftover
                tailPtr = movePtr sptr l
              in do
              -- Fills the source ptr from the end.
              --  sptr                tailPtr
              --   |                  |
              --   V                  V
              --   -----------------------------------------------------
              --   |   l              |    m                           |
              --   -----------------------------------------------------
              memcpy (destination ptr) (source tailPtr) m -- transfer the bytes to destination
              memset tailPtr 0 m                          -- wipe the bytes already transfered.
              setRemainingBytes l                         -- set leftover bytes.
              return m
