module Examples.Counter (spec, mainWidget) where

import Prelude hiding (append)

import Control.Monad.Cleanup (class MonadCleanup)
import Control.Monad.IOSync.Class (class MonadIOSync)
import Data.StrMap as SM
import Data.Tuple (Tuple(..))
import Specular.Dom.Widgets.Button (buttonOnClick)
import Specular.Dom.Browser (Node, innerHTML)
import Specular.Dom.Builder (Builder, domEventWithSample, dynText, el, elDynAttr', text)
import Specular.Dom.Node.Class (Attrs)
import Specular.FRP (Dynamic, Event, foldDyn, leftmost)
import Specular.FRP.Fix (fixFRP)
import Specular.FRP.WeakDynamic (WeakDynamic)
import Test.Spec (Spec, describe, it)
import Test.Spec.Runner (RunnerEffects)
import Test.Utils (ioSync, shouldReturn)
import Test.Utils.Dom (runBuilderInDiv, dispatchTrivialEvent, querySelector)

spec :: forall eff. Spec (RunnerEffects eff) Unit
spec = describe "Counter" $ do
  it "initially renders zero" $ do
    Tuple node _ <- runBuilderInDiv mainWidget

    ioSync (innerHTML node) `shouldReturn`
      ( """<p>0</p>""" <>
        """<button class="increment">Increment</button>""" <>
        """<button class="decrement">Decrement</button>"""
      )

  it "reacts to increment/decrement buttons" $ do
    Tuple node _ <- runBuilderInDiv mainWidget

    incrementButton <- ioSync $ querySelector ".increment" node
    decrementButton <- ioSync $ querySelector ".decrement" node

    ioSync $ dispatchTrivialEvent incrementButton "click"

    ioSync (innerHTML node) `shouldReturn`
      ( """<p>1</p>""" <>
        """<button class="increment">Increment</button>""" <>
        """<button class="decrement">Decrement</button>"""
      )

    ioSync $ dispatchTrivialEvent decrementButton "click"
    ioSync $ dispatchTrivialEvent decrementButton "click"
    ioSync $ dispatchTrivialEvent decrementButton "click"

    ioSync (innerHTML node) `shouldReturn`
      ( """<p>-2</p>""" <>
        """<button class="increment">Increment</button>""" <>
        """<button class="decrement">Decrement</button>"""
      )

mainWidget :: Builder Node Unit
mainWidget = fixFRP $ view >=> control

view ::
     { value :: WeakDynamic Int }
  -> Builder Node
    { increment :: Event Unit
    , decrement :: Event Unit
    }
view {value} = do
  el "p" $ dynText (show <$> value)

  increment <- buttonOnClick (pure $ SM.singleton "class" "increment") $ text "Increment"
  decrement <- buttonOnClick (pure $ SM.singleton "class" "decrement") $ text "Decrement"

  pure { increment, decrement }

control ::
     forall m
   . MonadIOSync m
  => MonadCleanup m
  => { increment :: Event Unit
     , decrement :: Event Unit
     }
  -> m (Tuple
    { value :: Dynamic Int }
    Unit
    )
control {increment,decrement} = do
  value <- foldDyn ($) 0 $
    leftmost
      [ (_ + 1) <$ increment
      , (_ - 1) <$ decrement
      ]
  pure (Tuple {value} unit)
