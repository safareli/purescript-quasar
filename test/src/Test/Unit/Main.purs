{-
Copyright 2017 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module Test.Unit.Main where

import Prelude

import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (CONSOLE, log)
import Data.Argonaut.Parser as JP
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Monoid (mempty)
import Data.NonEmpty as NE
import Data.String.NonEmpty (fromString)
import Data.These (These(..))
import Data.Time.Duration (Seconds(..))
import Data.Tuple (Tuple(..))
import Data.URI.AbsoluteURI as AbsoluteURI
import Quasar.Data.URI (portFromInt)
import Quasar.Data.URI as URI
import Quasar.Mount as QM
import Quasar.Mount.Couchbase as CB
import Quasar.Mount.MongoDB as Mongo
import Test.Assert (ASSERT, assert')
import Test.Property.Mount.Couchbase as CBT
import Text.Parsing.Parser (runParser)

main ∷ ∀ eff. Eff (assert ∷ ASSERT, console ∷ CONSOLE | eff) Unit
main = do

  log "Testing Unknown mount format parses"

  case QM.fromJSON =<< JP.jsonParser """{ "mongoish": { "connectionUri": "mongodb://localhost:63174" } }""" of
    Left err → fail $ "Config failed to parse: " <> show err
    Right (QM.UnknownConfig { mountType, connectionUri })
      | mountType == "mongoish" && connectionUri == "mongodb://localhost:63174" → pure unit
    Right conf → fail $ "Config failed to parse as expected, found: \n\n" <> show conf

  log "Testing Couchbase URI format parses as expected"

  testURIParse (map CBT.TestConfig <$> CB.fromURI)
    "couchbase://localhost/testBucket?password=&docTypeKey="
      (CBT.TestConfig
        { host: [ This (URI.NameAddress $ URI.unsafeRegNameFromString "localhost") ]
        , bucketName: fromString "testBucket"
        , password: ""
        , docTypeKey: ""
        , queryTimeout: Nothing
        })

  testURIParse (map CBT.TestConfig <$> CB.fromURI)
    "couchbase://localhost:99999/testBucket?password=pass&docTypeKey=type&queryTimeoutSeconds=20"
      (CBT.TestConfig
        { host: [Both (URI.NameAddress $ URI.unsafeRegNameFromString "localhost") (URI.unsafePortFromInt 99999)]
        , bucketName: fromString "testBucket"
        , password: "pass"
        , docTypeKey: "type"
        , queryTimeout: Just (Seconds (20.0))
        })
  let mongoURI =
        URI.qAbsoluteURI.print
          (Mongo.toURI
            { hosts: [Both (URI.NameAddress $ URI.unsafeRegNameFromString "localhost") (URI.unsafePortFromInt 12345)]
            , auth: Nothing
            , props: mempty})
  if mongoURI == "mongodb://localhost:12345/"
    then pure unit
    else fail ("Wrong MongoURI: " <> show mongoURI)

testURIParse
  ∷ ∀ a eff
  . Eq a
  ⇒ Show a
  ⇒ (URI.QAbsoluteURI → Either String a)
  → String
  → a
  → Eff (assert :: ASSERT | eff) Unit
testURIParse fromURI uri expected =
  case runParser uri URI.qAbsoluteURI.parser of
    Left err → fail $ "Test URI failed to parse as a URI even: \n\n\t" <> uri <> "\n\n\t" <> show err <> "\n\n"
    Right auri →
      case fromURI auri of
        Left err → fail $ "Test URI failed to parse as a config: \n\n\t" <> uri <> "\n\n\t" <> show err <> "\n\n"
        Right config
          | config == expected → pure unit
          | otherwise → fail $ "Test URI failed to parse as expected config: \n\n\t" <> uri <> "\n\n\tExpected: " <> show expected <> "\n\n\tActual: " <> show config <> "\n\n"

fail ∷ ∀ eff. String → Eff (assert :: ASSERT | eff) Unit
fail = flip assert' false
