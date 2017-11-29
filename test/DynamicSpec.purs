module DynamicSpec where

import Prelude hiding (append)

import Control.Monad.Cleanup (execCleanupT, runCleanupT)
import Data.IORef (newIORef)
import Data.Tuple (Tuple(..))
import Specular.FRP (holdDyn, newEvent, subscribeDyn_)
import Test.Spec (Spec, describe, it)
import Test.Spec.Runner (RunnerEffects)
import Test.Utils (append, clear, ioSync, shouldHaveValue)

spec :: forall eff. Spec (RunnerEffects eff) Unit
spec = describe "Dynamic" $ do

  describe "holdDyn" $ do
    it "updates value when someone is subscribed to changes" $ do
      {event,fire} <- ioSync newEvent
      log <- ioSync $ newIORef []
      Tuple dyn _ <- ioSync $ runCleanupT $ holdDyn 0 event

      unsub <- ioSync $ execCleanupT $ subscribeDyn_ (\x -> append log x) dyn
      log `shouldHaveValue` [0]

      clear log
      ioSync $ fire 1
      ioSync unsub
      ioSync $ fire 2

      log `shouldHaveValue` [1]

    it "updates value when no one is subscribed" $ do
      {event,fire} <- ioSync newEvent
      log <- ioSync $ newIORef []
      Tuple dyn _ <- ioSync $ runCleanupT $ holdDyn 0 event

      ioSync $ fire 2

      _ <- ioSync $ execCleanupT $ subscribeDyn_ (\x -> append log x) dyn

      log `shouldHaveValue` [2]

  describe "Applicative instance" $ do
    it "works with different root Dynamics" $ do
      ev1 <- ioSync newEvent
      ev2 <- ioSync newEvent
      log <- ioSync $ newIORef []
      Tuple rootDyn1 _ <- ioSync $ runCleanupT $ holdDyn 0 ev1.event
      Tuple rootDyn2 _ <- ioSync $ runCleanupT $ holdDyn 10 ev2.event

      let dyn = Tuple <$> rootDyn1 <*> rootDyn2
      _ <- ioSync $ execCleanupT $ subscribeDyn_ (\x -> append log x) dyn

      ioSync $ ev1.fire 1
      log `shouldHaveValue` [Tuple 0 10, Tuple 1 10]

      clear log
      ioSync $ ev2.fire 5
      log `shouldHaveValue` [Tuple 1 5]

    it "has no glitches when used with the same root Dynamic" $ do
      {event,fire} <- ioSync newEvent
      log <- ioSync $ newIORef []
      Tuple rootDyn _ <- ioSync $ runCleanupT $ holdDyn 0 event

      let dyn = Tuple <$> rootDyn <*> (map (_ + 10) rootDyn)
      _ <- ioSync $ execCleanupT $ subscribeDyn_ (\x -> append log x) dyn

      ioSync $ fire 1

      log `shouldHaveValue` [Tuple 0 10, Tuple 1 11]

  describe "Monad instance" $ do
    it "works" $ do
      ev1 <- ioSync newEvent
      ev2 <- ioSync newEvent
      log <- ioSync $ newIORef []
      Tuple rootDynInner _ <- ioSync $ runCleanupT $ holdDyn 0 ev1.event
      Tuple rootDynOuter _ <- ioSync $ runCleanupT $ holdDyn rootDynInner ev2.event

      let dyn = join rootDynOuter
      _ <- ioSync $ execCleanupT $ subscribeDyn_ (\x -> append log x) dyn
      log `shouldHaveValue` [0]
      clear log

      -- inner fires
      ioSync $ ev1.fire 1
      log `shouldHaveValue` [1]
      clear log

      -- outer fires
      ioSync $ ev2.fire (pure 2)
      log `shouldHaveValue` [2]
      clear log

      -- inner fires when outer not pointing to it
      ioSync $ ev1.fire 10
      log `shouldHaveValue` []

      -- outer fires to itself
      ioSync $ ev2.fire (3 <$ rootDynOuter)
      log `shouldHaveValue` [3]
      clear log

      -- outer fires to itself again
      ioSync $ ev2.fire (4 <$ rootDynOuter)
      log `shouldHaveValue` [4]
      clear log

      -- outer fires to inner
      ioSync $ ev2.fire rootDynInner
      log `shouldHaveValue` [10]
      clear log

      -- extra subscription should not mess things up
      _ <- ioSync $ execCleanupT $ subscribeDyn_ (\_ -> pure unit) dyn
      ioSync $ ev1.fire 15
      ioSync $ ev2.fire rootDynInner
      log `shouldHaveValue` [15, 15]