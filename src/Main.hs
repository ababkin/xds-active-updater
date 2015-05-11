{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

import           Control.Concurrent         (threadDelay)
import           Control.Lens               ((&), (.~))
import           Control.Monad              (forever)
import           Data.Aeson                 (FromJSON (parseJSON),
                                             ToJSON (toJSON), Value (Object),
                                             eitherDecode, encode, object, (.:),
                                             (.=))
import           Data.Aeson.Types           (typeMismatch)

import           Control.Applicative        ((<$>))
import           Control.Exception          as E
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Text                  as T
import           Network.HTTP.Client        (HttpException (StatusCodeException))
import           Network.Wreq               (Response, asJSON, defaults, get,
                                             header, postWith, responseBody)
import           System.Environment         (getEnv, lookupEnv)

import           Xds.Amqp                   (Status (Success, Failure), getAmqp,
                                             pollQueue, withAmqpChannel)

data RailsResponse = RailsResponse {
    status :: String
} deriving (Show)

instance FromJSON RailsResponse where
  parseJSON (Object v) = RailsResponse
    <$> (v .: "status")
  parseJSON o = typeMismatch "RailsResponse" o


incomingQ = "update"

main :: IO ()
main = do
  amqp <- getAmqp
  {- consumeMsgs chan incomingQ Ack handler -}

  withAmqpChannel amqp $ \chan ->
    pollQueue incomingQ chan 1000000 $ \message -> do
      putStrLn $ "UPDATE received: " ++ BL.unpack message
      case eitherDecode message of
        Left err -> do
          putStrLn $ "could not parse json: " ++ err
          return Failure
        Right (jsonMsg :: Value) -> do
          update jsonMsg `E.catch` handler

    where
      update :: Value -> IO Status
      update jsonMsg = do
        xdsHost <- getEnv "XDS_HOST"

        let url = "http://" ++ xdsHost ++ "/updates"
        let opts = defaults & header "Accept" .~ ["application/json"]
        jsonResp <- postWith opts url jsonMsg
        case asJSON jsonResp of
          Right (r :: Response RailsResponse) -> do
            print $ "received response: " ++ show r
            return Success
          Left err -> do
            print $ show err
            return Failure

      handler e@(StatusCodeException s _ _) = do
        putStrLn $ "status code exception: " ++ show s
        return Failure
      handler e = do
        putStrLn $ "generic exception: " ++ show e
        return Failure
