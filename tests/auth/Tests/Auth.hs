-- Generic tests for hash.
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MonoLocalBinds   #-}
module Tests.Auth
       ( authsTo
       ) where

import Implementation
import Interface
import Tests.Core



authsTo :: (Show Prim, Show (Key Prim), Eq Prim)
        => ByteString
        -> Prim
        -> Key Prim
        -> Spec
authsTo str prim key = it msg (auth key str `shouldBe` prim)
  where msg   = unwords [ "authenticates"
                        , shortened $ show str
                        , "to"
                        , shortened $ show prim
                        ]
