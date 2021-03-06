module Examples.AsyncRequest (spec, mainWidget) where

import Prelude hiding (append)

import BuilderSpec (newDynamic)
import Control.Monad.Aff (delay)
import Control.Monad.Aff.AVar (makeEmptyVar, putVar, takeVar)
import Control.Monad.Aff.Class (liftAff)
import Control.Monad.Eff.Class (liftEff)
import Control.Monad.Eff.Console (log)
import Control.Monad.IO (IO)
import Control.Monad.IOSync.Class (liftIOSync)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (Tuple(..))
import Specular.Dom.Browser (innerHTML)
import Specular.Dom.Builder.Class (el, text)
import Specular.Dom.Node.Class ((:=))
import Specular.Dom.Widget (class MonadWidget)
import Specular.Dom.Widgets.Input (textInputOnInput)
import Specular.FRP (Dynamic, current, dynamic_, hostEffect, newEvent, pull, readBehavior, weakDynamic_)
import Specular.FRP.Async (startIO)
import Specular.FRP.Base (holdDyn)
import Specular.FRP.Fix (fixFRP)
import Specular.FRP.WeakDynamic (WeakDynamic)
import Test.Spec (Spec, describe, it)
import Test.Spec.Runner (RunnerEffects)
import Test.Utils (ioSync, shouldReturn)
import Test.Utils.Dom (runBuilderInDiv)

spec :: forall eff. Spec (RunnerEffects eff) Unit
spec = describe "AsyncRequest" $ do
  it "initially renders empty form and empty result" $ do
    Tuple node _ <- runBuilderInDiv (mainWidgetWith instantBackend)

    ioSync (innerHTML node) `shouldReturn`
      ( """<div><label>Input: </label><input class="login"></div>""" <>
        """<div></div>"""
      )

  describe "logic" $ do
    it "renders request state" $ do
      avar <- makeEmptyVar
      let backend = { toUpper: \_ -> liftAff $ takeVar avar }
      Tuple query setQuery <- ioSync $ newDynamic ""

      Tuple _ (Tuple {result} _) <- runBuilderInDiv $ control backend {query}
      ioSync (pull $ readBehavior $ current result) `shouldReturn` NotRequested

      ioSync $ setQuery "foo"
      ioSync (pull $ readBehavior $ current result) `shouldReturn` Loading

      putVar "FOO" avar
      ioSync (pull $ readBehavior $ current result) `shouldReturn` Loaded "FOO"

    it "always displays the latest request" $ do
      firstRequest <- makeEmptyVar
      secondRequest <- makeEmptyVar
      currentRequestVar <- ioSync $ newIORef firstRequest
      let backend = { toUpper: \_ -> do
                        var <- liftIOSync $ readIORef currentRequestVar
                        liftAff $ takeVar var
                    }
      Tuple query setQuery <- ioSync $ newDynamic ""

      Tuple _ (Tuple {result} _) <- runBuilderInDiv $ control backend {query}

      ioSync $ setQuery "foo"
      ioSync $ writeIORef currentRequestVar secondRequest
      ioSync $ setQuery "bar"

      putVar "FOO" firstRequest
      ioSync (pull $ readBehavior $ current result) `shouldReturn` Loading

      putVar "BAR" secondRequest
      ioSync (pull $ readBehavior $ current result) `shouldReturn` Loaded "BAR"


instantBackend :: Backend
instantBackend = { toUpper: pure <<< String.toUpper }

slowBackend :: Backend
slowBackend = { toUpper }
  where
    toUpper s = do
      liftEff $ log $ "Request started:  " <> show s
      liftAff $ delay (Milliseconds 1200.0)
      liftEff $ log $ "Request finished: " <> show s
      pure (String.toUpper s)

type Backend =
  { toUpper :: String -> IO String
  }

mainWidget :: forall m. MonadWidget m => m Unit
mainWidget = mainWidgetWith slowBackend

mainWidgetWith :: forall m. MonadWidget m => Backend -> m Unit
mainWidgetWith backend = fixFRP $ view >=> control backend

data Loading a = NotRequested | Loading | Loaded a

derive instance eqLoading :: Eq a => Eq (Loading a)

instance showLoading :: Show a => Show (Loading a) where
  show NotRequested = "NotRequested"
  show Loading = "Loading"
  show (Loaded x) = "(Loaded " <> show x <> ")"

view :: forall m. MonadWidget m
  => { result :: WeakDynamic (Loading String) }
  -> m { query :: Dynamic String }
view {result} = do
  query <- el "div" $ do
    el "label" $ text "Input: "
    textInputOnInput "" ("class" := "login")

  el "div" $ do
    weakDynamic_ $ flip map result $
      case _ of
        NotRequested -> pure unit
        Loading -> text $ "Accessing Webscale Uppercase Service..."
        Loaded x -> text $ "Result is: " <> x

  pure { query }

control :: forall m. MonadWidget m
  => Backend
  -> { query :: Dynamic String }
  -> m (Tuple
    { result :: Dynamic (Loading String) }
    Unit
    )
control backend {query} = do
  loadStateChanged <- newEvent

  dynamic_ $ flip map query $ \queryValue ->
    if queryValue == ""
      then
        hostEffect $ loadStateChanged.fire NotRequested
      else
        startIO $ do
          liftIOSync $ loadStateChanged.fire Loading
          value <- backend.toUpper queryValue
          liftIOSync $ loadStateChanged.fire (Loaded value)

  result <- holdDyn NotRequested loadStateChanged.event
  pure $ Tuple { result } unit
