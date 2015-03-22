{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

import           Control.Concurrent         (threadDelay)
import           Control.Monad              (forever)
import           Data.Aeson                 (FromJSON (parseJSON),
                                             ToJSON (toJSON), Value (Object),
                                             eitherDecode, encode, object, (.:),
                                             (.=))
import           Data.Aeson.Types           (typeMismatch)

import           Control.Applicative        ((<$>))
import qualified Data.ByteString.Lazy.Char8 as BL
import qualified Data.Text                  as T
import           Network.AMQP               (Ack (..), Connection, Envelope,
                                             Message, QueueOpts (..), ackEnv,
                                             bindQueue, consumeMsgs,
                                             declareQueue, getMsg, msgBody,
                                             newQueue, openChannel,
                                             openConnection, rejectEnv)
import           Network.Wreq               (Response, asJSON, get, post,
                                             responseBody)
import           System.Environment         (getEnv, lookupEnv)


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
  rmqIp       <- getEnv "RMQ_IP"
  rmqPort     <- getEnv "RMQ_PORT"
  rmqUsername <- getEnv "RMQ_USERNAME"
  rmqPassword <- getEnv "RMQ_PASSWORD"

  rmqConn     <- openConnection rmqIp "/" (T.pack rmqUsername) (T.pack rmqPassword)

  chan <- openChannel rmqConn
  {- consumeMsgs chan incomingQ Ack handler -}

  forever $ do
    threadDelay 1000000
    maybeMsg <- getMsg chan Ack incomingQ
    case maybeMsg of
      Nothing -> return ()
      Just (msg, env) -> do
        let message = msgBody msg
        putStrLn $ "UPDATE received: " ++ BL.unpack message

        {- result <- jsonResult $ msgBody msg -}

        {- chan <- openChannel conn -}
        {- publishMsg chan "" outgoingQ -}
          {- -- What to use for Id ? -}
          {- newMsg {msgBody         = result, -}
                  {- msgDeliveryMode = Just Persistent} -}
        case eitherDecode message of
          Left err ->
            putStrLn $ "could not parse json: " ++ err
          Right (jsonMsg :: Value) -> do
            xdsHost <- getEnv "XDS_HOST"

            let url = "http://" ++ xdsHost ++ "/updates.json"
            jsonResp <- post url jsonMsg
            case asJSON jsonResp of
              Right (r :: Response RailsResponse) -> do
                print $ "received response: " ++ show r
                {- SearchResponse $ map hDataset $ hsHits $ srHits (r ^. responseBody) -}
                ackEnv env
              Left err -> do
                print $ show err
                rejectEnv env True

