{-# LANGUAGE TemplateHaskell,
             ScopedTypeVariables,
             StandaloneDeriving,
             DeriveAnyClass,
             DeriveGeneric,
             DataKinds,
             TypeOperators,
             TypeFamilies,
             FlexibleContexts,
             NumericUnderscores,
             UnboxedTuples #-}
module Main where
import Parsers (BrainFuckOp(..))
import qualified Parsers
import qualified Parsley
import Data.Int
import Data.Char (ord, chr)

parseBrainfuck :: String -> IO (Maybe [BrainFuckOp])
parseBrainfuck = $$(Parsley.parseFromFile Parsers.brainfuck)

data Tape a = Tape [a] a [a]

evalBf :: [BrainFuckOp] -> IO ()
evalBf prog = go (Tape (repeat 0) 0 (repeat 0)) prog >> return ()
  where
    evalOp :: BrainFuckOp -> Tape Int32 -> IO (Tape Int32)
    evalOp RightPointer tape =                      return (right tape)
    evalOp LeftPointer  tape =                      return (left tape)
    evalOp Increment    tape = let x = read tape in return (write (succ x) tape)
    evalOp Decrement    tape = let x = read tape in return (write (pred x) tape)
    evalOp Output       tape = let x = read tape in do print (chr (fromEnum x)); return tape
    evalOp Input        tape =                      do x <- getChar; return (write (toEnum (ord x)) tape)
    evalOp (Loop p)     tape = let x = read tape in if x == 0 then return tape
                                                    else do tape' <- go tape p
                                                            if read tape' /= 0 then evalOp (Loop p) tape'
                                                            else return tape'

    go :: Tape Int32 -> [BrainFuckOp] -> IO (Tape Int32)
    go tape [] = return tape
    go tape (op:ops) = do tape' <- evalOp op tape; go tape' ops

    right :: Tape a -> Tape a
    right (Tape ls x (r:rs)) = Tape (x:ls) r rs
    left :: Tape a -> Tape a
    left (Tape (l:ls) x rs) = Tape ls l (x:rs)
    read :: Tape a -> a
    read (Tape _ x _) = x
    write :: a -> Tape a -> Tape a
    write x (Tape ls _ rs) = Tape ls x rs

--javascript :: String -> Maybe JSProgram
--javascript = $$(Parsley.runParser Parsers.javascript)

boom :: String -> Maybe ()
boom = $$(Parsley.runParser Parsers.failure)

nfb :: String -> Maybe ()
nfb = $$(Parsley.runParser Parsers.nfb)

main :: IO ()
main =
  do res <- parseBrainfuck "inputs/helloworld.bf"
     print res
     print (nfb "a")
     print (nfb "ab")
     print (nfb "c")
     return ()