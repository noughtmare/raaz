{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE CPP                 #-}
import           Control.Monad
import           Criterion
import           Criterion.Main
import           Criterion.Types
import           Data.Proxy
import           Foreign.Marshal.Alloc

import           Raaz.Core
import           Raaz.Cipher
import           Raaz.Cipher.Internal
import qualified Raaz.Cipher.ChaCha20.Implementation.CPortable as CPortable

-- | Buffer size used
bufSize :: BYTES Int
bufSize = 32 * 1024


main :: IO ()
main = defaultMain [ chacha20Bench ]


----------------- Benchmarks of individual ciphers. ------------------------

chacha20Bench :: Benchmark
chacha20Bench = bgroup "ChaCha20"
                [ benchEncrypt' chacha20 $ SomeCipherI CPortable.implementation ]


------------------ Low level functions ---------------------------------------
benchCipher :: (Cipher c, Recommendation c) => c  -> Benchmark
benchCipher c = bgroup (name c) [benchEncrypt c, benchDecrypt c]

benchEncrypt :: (Cipher c, Recommendation c) => c -> Benchmark
benchEncrypt c = benchEncrypt' c $ recommended $ proxy c

benchDecrypt  :: (Cipher c, Recommendation c) => c -> Benchmark
benchDecrypt c = benchDecrypt' c $ recommended $ proxy c


benchEncrypt' :: Cipher c => c -> Implementation c -> Benchmark
benchEncrypt' c si@(SomeCipherI imp) = bench nm $ nfIO go
  where go = allocBufferFor si sz $ \ ptr -> insecurely $ encryptBlocks imp ptr sz
        sz = atMost bufSize
        nm = "encrypt" ++ name si

benchDecrypt' :: Cipher c => c -> Implementation c -> Benchmark
benchDecrypt' c si@(SomeCipherI imp) = bench nm $ nfIO go
  where go = allocBufferFor si sz $ \ ptr -> insecurely $ decryptBlocks imp ptr sz
        sz = atMost bufSize
        nm = "decrypt" ++ name si

proxy :: a -> Proxy a
proxy _ = Proxy
