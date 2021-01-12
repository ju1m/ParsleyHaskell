{-# LANGUAGE TemplateHaskell, UnboxedTuples #-}
module Parsley.Selective.Test where
import Test.Tasty

tests :: TestTree
tests = testGroup "Selective" [ selectTests
                              , filterTests
                              , predicateTests
                              , sbindTests
                              , whenTests
                              , whileTests
                              , fromMaybePTests
                              ]

selectTests :: TestTree
selectTests = testGroup "select should" []

filterTests :: TestTree
filterTests = testGroup "filter should" [] -- >??>, >?>, filteredBy

predicateTests :: TestTree
predicateTests = testGroup "predicate should" [] -- <?:>

sbindTests :: TestTree
sbindTests = testGroup "sbind should" [] -- match

whenTests :: TestTree
whenTests = testGroup "when should" []

whileTests :: TestTree
whileTests = testGroup "while should" []

fromMaybePTests :: TestTree
fromMaybePTests = testGroup "fromMaybeP should" []