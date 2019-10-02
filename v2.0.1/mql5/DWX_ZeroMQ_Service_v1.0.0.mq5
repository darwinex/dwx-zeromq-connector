//+-------------------------------------------------------------------+
//|     DWX_ZeroMQ_Service_v1.0.0.mq5                                 |
//|     Based on DWX_ZeroMQ_Server_v2.0.1_RC8.mq4                     |
//|     @author: Darwinex Labs (www.darwinex.com)                     |
//|                                                                   |
//|     Last Updated: October 02, 2019                                |
//|                                                                   |
//|     Copyright (c) 2017-2019, Darwinex. All rights reserved.       |
//|                                                                   |
//|     Licensed under the BSD 3-Clause License, you may not use this |
//|     file except in compliance with the License.                   |
//|                                                                   |
//|     You may obtain a copy of the License at:                      |
//|     https://opensource.org/licenses/BSD-3-Clause                  |
//+-------------------------------------------------------------------+
#property service
#property copyright "Copyright 2017-2019, Darwinex Labs."
#property link      "https://www.darwinex.com/"
#property version   "1.0.0"

// Required: MQL-ZMQ from https://github.com/dingmaotu/mql-zmq
#include <Zmq/Zmq.mqh>
// Transactions helper class From Standard Library
#include <Trade/Trade.mqh>
//+------------------------------------------------------------------+
//|  Enumerations to simplify client-server communication            |
//+------------------------------------------------------------------+
// NOTE: There is not too many actions and all could be replaced
// by one number. No need to send and process
// two strings: TRADE|DATA and ACTION.
enum ENUM_DWX_SERV_ACTION
  {
   HEARTBEAT=0,
   POS_OPEN=1,
   POS_MODIFY=2,
   POS_CLOSE=3,
   POS_CLOSE_PARTIAL=4,
   POS_CLOSE_MAGIC=5,
   POS_CLOSE_ALL=6,
   ORD_OPEN=7,
   ORD_MODIFY=8,
   ORD_DELETE=9,
   ORD_DELETE_ALL=10,
   GET_POSITIONS=11,
   GET_PENDING_ORDERS=12,
   GET_DATA=13,
   GET_TICK_DATA=14
  };

input string PROJECT_NAME="DWX_ZeroMQ_MT5_Server";
input string ZEROMQ_PROTOCOL="tcp";
input string HOSTNAME="*";
input int PUSH_PORT = 32768;
input int PULL_PORT = 32769;
input int PUB_PORT=32770;
// Real max. time resolution of Sleep() and Timer() function
// is usually >= 10-16 milliseconds. This is due to
// hardware limitations in typical OS configuration.
input int REFRESH_INTERVAL=1;

input string t0="--- Trading Parameters ---";
input int MagicNumber=123456;
input int MaximumOrders=1;
input double MaximumLotSize=0.01;
input int MaximumSlippage=3;
input string t1="--- ZeroMQ Configuration ---";
input bool Publish_MarketData=false;
input bool Verbose=true;

string Publish_Symbols[7]={"EURUSD","GBPUSD","USDJPY","USDCAD","AUDUSD","NZDUSD","USDCHF"};
ulong  Last_MqlTicks_Times_Msc[7];
int Publish_Symbols_Digits[7];

/*
string Publish_Symbols[28] = {
   "EURUSD","EURGBP","EURAUD","EURNZD","EURJPY","EURCHF","EURCAD",
   "GBPUSD","AUDUSD","NZDUSD","USDJPY","USDCHF","USDCAD","GBPAUD",
   "GBPNZD","GBPJPY","GBPCHF","GBPCAD","AUDJPY","CHFJPY","CADJPY",
   "AUDNZD","AUDCHF","AUDCAD","NZDJPY","NZDCHF","NZDCAD","CADCHF"
};
ulong  Last_MqlTicks_Times_Msc[28];
int Publish_Symbols_Digits[28];
*/
// CREATE ZeroMQ Context
Context context(PROJECT_NAME);

// CREATE ZMQ_PUSH SOCKET
Socket pushSocket(context,ZMQ_PUSH);

// CREATE ZMQ_PULL SOCKET
Socket pullSocket(context,ZMQ_PULL);

// CREATE ZMQ_PUB SOCKET
Socket pubSocket(context,ZMQ_PUB);

// VARIABLES FOR LATER
uchar _data[];
ZmqMsg zmq_request;

// Object to perform transactions.
// In MQL5 transactions management is much more complicated than
// in MQL4. Using CTrade class will be the best idea in this case.
CTrade tradeHelper;
//+------------------------------------------------------------------+
//| Service program start function                                   |
//+------------------------------------------------------------------+
void OnStart()
  {
   if(!ServiceInit())
     {
      Print("Service initialization failed!");
      //Clean up before leave
      ServiceDeinit();
      return;
     }

// while(!IsStopped())
   while(CheckServiceStatus())
     {
      if(Publish_MarketData)
        {
         CollectAndPublish();
        }

      // Code section used to get and respond to commands
      if(CheckServiceStatus())
        {
         // Get client's response, but don't block.
         pullSocket.recv(zmq_request,true);

         if(zmq_request.size()>0)
            MessageHandler(zmq_request);
        }

      Sleep(REFRESH_INTERVAL);
     }
   ServiceDeinit();
  }
//+------------------------------------------------------------------+
//|  Service initialization function                                 |
//+------------------------------------------------------------------+
bool ServiceInit(void)
  {
   bool init_result=false;
   context.setBlocky(false);
/* Set Socket Options */

// Send responses to PULL_PORT that client is listening on.
   pushSocket.setSendHighWaterMark(1);
   pushSocket.setLinger(0);
   Print("[PUSH] Binding MT5 Server to Socket on Port "+IntegerToString(PULL_PORT)+"..");
   init_result=init_result || pushSocket.bind(StringFormat("%s://%s:%d",ZEROMQ_PROTOCOL,HOSTNAME,PULL_PORT));

// Receive commands from PUSH_PORT that client is sending to.
   pullSocket.setReceiveHighWaterMark(1);
   pullSocket.setLinger(0);
   Print("[PULL] Binding MT5 Server to Socket on Port "+IntegerToString(PUSH_PORT)+"..");
   init_result=init_result || pullSocket.bind(StringFormat("%s://%s:%d",ZEROMQ_PROTOCOL,HOSTNAME,PUSH_PORT));

   if(Publish_MarketData==true)
     {
      // Send new market data to PUB_PORT that client is subscribed to.
      pubSocket.setSendHighWaterMark(1);
      pubSocket.setLinger(0);
      Print("[PUB] Binding MT5 Server to Socket on Port "+IntegerToString(PUB_PORT)+"..");
      init_result=init_result || pubSocket.bind(StringFormat("%s://%s:%d",ZEROMQ_PROTOCOL,HOSTNAME,PUB_PORT));

      // Here last ticks timestamps for all 'Publish_Symbols' are collected.
      // See 'CollectAndPublish' function.
      MqlTick last_tick;
      ulong time_current_msc=TimeCurrent()*1000;
      for(int i=0; i<ArraySize(Publish_Symbols); i++)
        {
         if(SymbolInfoTick(Publish_Symbols[i],last_tick))
           {
            Last_MqlTicks_Times_Msc[i]=last_tick.time_msc;
           }
         else
           {
            Last_MqlTicks_Times_Msc[i]=time_current_msc;
           }
         // collecting '_Digits' for each symbol
         Publish_Symbols_Digits[i]=(int)SymbolInfoInteger(Publish_Symbols[i],SYMBOL_DIGITS);
        }
     }

// Setting up few attributes of trading management object.
// By default 'tradeHelper' will work only with trades placed by itself.
   tradeHelper.SetExpertMagicNumber(MagicNumber);
   tradeHelper.SetMarginMode();
   tradeHelper.SetDeviationInPoints(MaximumSlippage);
   tradeHelper.SetAsyncMode(false);

   Print("'"+PROJECT_NAME+"' started.");
   return init_result;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void ServiceDeinit(void)
  {
   Print("[PUSH] Unbinding MT5 Server from Socket on Port "+IntegerToString(PULL_PORT)+"..");
   pushSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PULL_PORT));
   pushSocket.disconnect(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PULL_PORT));

   Print("[PULL] Unbinding MT5 Server from Socket on Port "+IntegerToString(PUSH_PORT)+"..");
   pullSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));
   pullSocket.disconnect(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUSH_PORT));

   if(Publish_MarketData==true)
     {
      Print("[PUB] Unbinding MT5 Server from Socket on Port "+IntegerToString(PUB_PORT)+"..");
      pubSocket.unbind(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUB_PORT));
      pubSocket.disconnect(StringFormat("%s://%s:%d", ZEROMQ_PROTOCOL, HOSTNAME, PUB_PORT));
     }

// Destroy ZeroMQ Context
   context.destroy(0);

   Print("'"+PROJECT_NAME+"' stopped.");
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool CheckServiceStatus()
  {
   if(IsStopped())
     {
      InformPullClient(pullSocket,"{'_response': 'SERVICE_IS_STOPPED'}");
      return(false);
     }
   return(true);
  }
//+------------------------------------------------------------------+
//|  Procedure collecting and publishing new rates data              |
//+------------------------------------------------------------------+
// Unlike using functions 'OnTick' and 'SymbolInfoTick'      
// here no any new quote will be missed. Additionally every rate   
// will be sent only once.                                         
// Note: If mql4|mql5 application queue already contains NewTick event
// or OnTick|OnCalculate function is been executed no new NewTick event
// is added to the queue. The terminal can simultaneously receive
// few ticks but OnTick procedure will be called only once.
void CollectAndPublish(void)
  {
   MqlTick tick_array[];
   for(int i=0; i<ArraySize(Publish_Symbols); i++)
     {
      // There might be many, one or no new ticks since last data sent.
      // Checking ticks one millisecond newer than the last one sent.
      int received=CopyTicks(Publish_Symbols[i],tick_array,COPY_TICKS_ALL,Last_MqlTicks_Times_Msc[i]+1);
      if(received>0)
        {
         string data_str="";
         for(int j=0;j<received;j++)
           {
            // '#' - single tick data delimiter (if more than one new tick)
            if(data_str!="")
               data_str+="#";
            // Note: time in milliseconds since 1970.01.01 00:00:00.001. To be formatted on client side.
            // Note 2: date sent in mql string format: 23 bytes, raw miliseconds: 13 bytes 
            data_str+=IntegerToString(tick_array[j].time_msc)
                      +";"+DoubleToString(tick_array[j].bid,Publish_Symbols_Digits[i])+";"
                      +DoubleToString(tick_array[j].ask,Publish_Symbols_Digits[i]);
           }
         // Data published in format:
         // 'SYMBOL_NAME MILISECONDS;BID_PRICE;ASK_PRICE#MILISECONDS;BID_PRICE;ASK_PRICE....'
         string data_to_pub=StringFormat("%s %s",Publish_Symbols[i],data_str);
         if(Verbose)
            Print("Sending "+data_to_pub+" to PUB Socket");

         ZmqMsg pushReply(data_to_pub);
         pubSocket.send(pushReply,true); // NON-BLOCKING

         Last_MqlTicks_Times_Msc[i]=tick_array[received-1].time_msc;
        }
     }
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void MessageHandler(ZmqMsg &_request)
  {
   string components[10];

   if(_request.size()>0)
     {
      // Get data from request   
      ArrayResize(_data,(int)(_request.size()));
      _request.getData(_data);
      string dataStr=CharArrayToString(_data);
      Print(dataStr);

      // Process data
      ParseZmqMessage(dataStr,components);

      // Interpret data
      InterpretZmqMessage(pushSocket,components);
     }
  }
//+------------------------------------------------------------------+
//|  Interpret Zmq Message and perform actions                       |
//+------------------------------------------------------------------+
void InterpretZmqMessage(Socket &pSocket,string &compArray[])
  {
// IMPORTANT NOTE: In MT5 there are ORDERS (market, pending),
// POSITIONS which are result of one or more DEALS.
// Already closed POSITIONS can be accessed only by corresponding DEALS.
// IMPORTANT NOTE2: size of compArray is 10, not 11 as in original version!
// Message Structures:

// 1) Trading
// ENUM_DWX_SERV_ACTION[from 1 to 10]|TYPE|SYMBOL|PRICE|SL|TP|COMMENT|MAGIC|VOLUME|TICKET
// e.g. POS_OPEN|1|EURUSD|0|50|50|Python-to-MetaTrader5|12345678|0.01

// The 12345678 at the end is the ticket ID, for MODIFY and CLOSE.

// 2) Data Requests: DWX_SERV_ACTION = GET_DATA (OHLC and candle open time)
// or GET_TICK_DATA (tick time in millisecond, bid, ask)
// 2.1) GET_DATA|SYMBOL|TIMEFRAME|START_DATETIME|END_DATETIME
// 2.2) GET_TICK_DATA|SYMBOL|START_DATETIME|END_DATETIME

// NOTE: datetime has format: 'YYYY.MM.DD hh:mm:ss'

/*
      If compArray[0] = ACTION: one from [POS_OPEN,POS_MODIFY,POS_CLOSE,
         POS_CLOSE_PARTIAL,POS_CLOSE_MAGIC,POS_CLOSE_ALL,ORD_OPEN,ORD_MODIFY,ORD_DELETE,ORD_DELETE_ALL]
         compArray[1] = TYPE: one from [ORDER_TYPE_BUY,ORDER_TYPE_SELL only used when ACTION=POS_OPEN]
         or from [ORDER_TYPE_BUY_LIMIT,ORDER_TYPE_SELL_LIMIT,ORDER_TYPE_BUY_STOP,
         ORDER_TYPE_SELL_STOP only used when ACTION=ORD_OPEN]
         
         ORDER TYPES: 
         https://www.mql5.com/en/docs/constants/tradingconstants/orderproperties#enum_order_type
         
         ORDER_TYPE_BUY = 0
         ORDER_TYPE_SELL = 1
         ORDER_TYPE_BUY_LIMIT = 2
         ORDER_TYPE_SELL_LIMIT = 3
         ORDER_TYPE_BUY_STOP = 4
         ORDER_TYPE_SELL_STOP = 5
         
         In this version ORDER_TYPE_BUY_STOP_LIMIT, ORDER_TYPE_SELL_STOP_LIMIT
         and ORDER_TYPE_CLOSE_BY are ignored.
         
         compArray[2] = Symbol (e.g. EURUSD, etc.)
         compArray[3] = Open/Close Price (ignored if ACTION = POS_MODIFY|ORD_MODIFY)
         compArray[4] = SL
         compArray[5] = TP
         compArray[6] = Trade Comment
         compArray[7] = Lots
         compArray[8] = Magic Number
         compArray[9] = Ticket Number (all type of modify|close|delete)
   */

// Only simple number to process
   ENUM_DWX_SERV_ACTION switch_action=(ENUM_DWX_SERV_ACTION)StringToInteger(compArray[0]);

/* Setup processing variables */
   string zmq_ret="";
   string ret = "";
   int ticket = -1;
   bool ans=false;

/****************************
    * PERFORM SOME CHECKS HERE *
    ****************************/
   if(CheckOpsStatus(pSocket,(int)switch_action)==true)
     {
      switch(switch_action)
        {
         case HEARTBEAT:

            InformPullClient(pSocket,"{'_action': 'heartbeat', '_response': 'loud and clear!'}");
            break;

         case POS_OPEN:

            zmq_ret="{";
            ticket=DWX_PositionOpen(compArray[2],(int)StringToInteger(compArray[1]),StringToDouble(compArray[7]),
                                    StringToDouble(compArray[3]),(int)StringToInteger(compArray[4]),(int)StringToInteger(compArray[5]),
                                    compArray[6],(int)StringToInteger(compArray[8]),zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");
            break;

         case POS_MODIFY:

            zmq_ret="{'_action': 'POSITION_MODIFY'";
            ans=DWX_PositionModify((int)StringToInteger(compArray[9]),StringToDouble(compArray[4]),StringToDouble(compArray[5]),zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case POS_CLOSE:

            zmq_ret="{";
            DWX_PositionClose_Ticket((int)StringToInteger(compArray[9]),zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case POS_CLOSE_PARTIAL:

            zmq_ret="{";
            ans=DWX_PositionClosePartial(StringToDouble(compArray[7]),zmq_ret,(int)StringToInteger(compArray[9]));
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case POS_CLOSE_MAGIC:

            zmq_ret="{";
            DWX_PositionClose_Magic((int)StringToInteger(compArray[8]),zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case POS_CLOSE_ALL:

            zmq_ret="{";
            DWX_PositionsClose_All(zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case ORD_OPEN:

            zmq_ret="{";
            ticket=DWX_OrderOpen(compArray[2],(int)StringToInteger(compArray[1]),StringToDouble(compArray[7]),
                                 StringToDouble(compArray[3]),(int)StringToInteger(compArray[4]),(int)StringToInteger(compArray[5]),
                                 compArray[6],(int)StringToInteger(compArray[8]),zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case ORD_MODIFY:

            zmq_ret="{'_action': 'ORDER_MODIFY'";
            ans=DWX_OrderModify((int)StringToInteger(compArray[9]),StringToDouble(compArray[4]),StringToDouble(compArray[5]),zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case ORD_DELETE:

            zmq_ret="{";
            DWX_PendingOrderDelete_Ticket((int)StringToInteger(compArray[9]),zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case ORD_DELETE_ALL:

            zmq_ret="{";
            DWX_PendingOrderDelete_All(zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case GET_POSITIONS:

            zmq_ret="{";
            DWX_GetOpenPositions(zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case GET_PENDING_ORDERS:

            zmq_ret="{";
            DWX_GetPendingOrders(zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case GET_DATA:

            zmq_ret="{";
            DWX_GetData(compArray,zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         case GET_TICK_DATA:

            zmq_ret="{";
            DWX_GetTickData(compArray,zmq_ret);
            InformPullClient(pSocket,zmq_ret+"}");

            break;
         default:
            break;
        }
     }
  }
//+------------------------------------------------------------------+
//|  Check if operations are permitted                               |
//+------------------------------------------------------------------+
bool CheckOpsStatus(Socket &pSocket,int sFlag)
  {
   if(sFlag<=10 && sFlag>0)
     {
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
         InformPullClient(pSocket,"{'_response': 'TRADING_IS_NOT_ALLOWED__ABORTED_COMMAND'}");
         return(false);
        }
      else if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
        {
         InformPullClient(pSocket,"{'_response': 'EA_IS_DISABLED__ABORTED_COMMAND'}");
         return(false);
        }
      else if(!TerminalInfoInteger(TERMINAL_DLLS_ALLOWED))
        {
         InformPullClient(pSocket,"{'_response': 'DLLS_DISABLED__ABORTED_COMMAND'}");
         return(false);
        }
      else if(!MQLInfoInteger(MQL_DLLS_ALLOWED))
        {
         InformPullClient(pSocket,"{'_response': 'LIBS_DISABLED__ABORTED_COMMAND'}");
         return(false);
        }
      else if(!TerminalInfoInteger(TERMINAL_CONNECTED))
        {
         InformPullClient(pSocket,"{'_response': 'NO_BROKER_CONNECTION__ABORTED_COMMAND'}");
         return(false);
        }
     }
   return(true);
  }
//+------------------------------------------------------------------+
//|  Parse Zmq Message                                               |
//+------------------------------------------------------------------+
void ParseZmqMessage(string &message,string &retArray[])
  {
   string sep=";";
   ushort u_sep=StringGetCharacter(sep,0);
   int splits=StringSplit(message,u_sep,retArray);
  }
//+------------------------------------------------------------------+
//|  Get data for request datetime range                             |
//+------------------------------------------------------------------+
void DWX_GetData(string &compArray[],string &zmq_ret)
  {
// GET_DATA == 13
// Format: 13|SYMBOL|TIMEFRAME|START_DATETIME|END_DATETIME

   double open_array[],high_array[],low_array[],close_array[];
   datetime time_array[];

// Get open prices
   int open_count=CopyOpen(compArray[1],
                           (ENUM_TIMEFRAMES)StringToInteger(compArray[2]),StringToTime(compArray[3]),
                           StringToTime(compArray[4]),open_array);
// Get close prices
   int close_count=CopyClose(compArray[1],
                             (ENUM_TIMEFRAMES)StringToInteger(compArray[2]),StringToTime(compArray[3]),
                             StringToTime(compArray[4]),close_array);
// Get high prices
   int high_count=CopyHigh(compArray[1],
                           (ENUM_TIMEFRAMES)StringToInteger(compArray[2]),StringToTime(compArray[3]),
                           StringToTime(compArray[4]),high_array);
// Get low prices
   int low_count=CopyLow(compArray[1],
                         (ENUM_TIMEFRAMES)StringToInteger(compArray[2]),StringToTime(compArray[3]),
                         StringToTime(compArray[4]),low_array);
// Get open time
   int time_count=CopyTime(compArray[1],
                           (ENUM_TIMEFRAMES)StringToInteger(compArray[2]),StringToTime(compArray[3]),
                           StringToTime(compArray[4]),time_array);

   zmq_ret+="'_action': 'GET_DATA'";

   if(time_count>0 && (time_count==open_count && time_count==close_count
      && time_count==high_count && time_count==low_count))
     {
      zmq_ret+=", '_ohlc_data': {";

      for(int i=0; i<time_count; i++)
        {
         if(i>0)
            zmq_ret+=", ";

         zmq_ret+="'"+TimeToString(time_array[i])+"': ["+DoubleToString(open_array[i])
                  +", "+DoubleToString(high_array[i])+", "+DoubleToString(low_array[i])
                  +", "+DoubleToString(close_array[i])+"]";
        }
      zmq_ret+="}";
     }
   else
     {
      zmq_ret+=", "+"'_response': 'NOT_AVAILABLE'";
     }
  }
//+------------------------------------------------------------------+
//|  Using this function for the first time for given symbol and time|
//|  period may halt the service for up to 45 seconds. During this   |
//|  time synchronization between local symbol's database and        |
//|  server's database (broker) should be completed.                 |
//+------------------------------------------------------------------+
void DWX_GetTickData(string &compArray[],string &zmq_ret)
  {
// GET_TICK_DATA == 14
// Format: 14|SYMBOL|START_DATETIME|END_DATETIME

   datetime d0 = StringToTime(compArray[2]);
   datetime d1 = StringToTime(compArray[3]);
   zmq_ret+="'_action': 'GET_TICK_DATA'";
   if(d0>0)
     {
      MqlTick tck_array[];
      int copied=-1;
      ResetLastError();
      // COPY_TICKS_ALL - fastest
      // COPY_TICKS_INFO – ticks with Bid and/or Ask changes
      // COPY_TICKS_TRADE – ticks with changes in Last and Volume
      if(d1>0)
        {
         copied=CopyTicksRange(compArray[1],tck_array,COPY_TICKS_ALL,(ulong)(d0*1000),(ulong)(d1*1000));
        }
      else
        {
         copied=CopyTicks(compArray[1],tck_array,COPY_TICKS_ALL,(ulong)(d0*1000));
        }
      // Error while using 'Copy' function
      if(copied==-1)
        {
         Add_Error_Description(GetLastError(),zmq_ret);
        }
      else if(copied==0)
        {
         zmq_ret+=", "+"'_response': 'NO_TICKS_AVAILABLE'";
        }
      else
        {
         zmq_ret+=", '_data': {";

         for(int i=0; i<copied; i++)
           {
            if(i>0)
               zmq_ret+=", ";

            zmq_ret+="'"+TimeToString((long)(tck_array[i].time_msc/1000.0),TIME_DATE|TIME_SECONDS)
                     +"."+IntegerToString((long)fmod(tck_array[i].time_msc,1000),3,'0')
                     +"': ["+DoubleToString(tck_array[i].bid)+", "+DoubleToString(tck_array[i].ask)+"]";
           }
         zmq_ret+="}";
        }
     }
   else
     {
      zmq_ret+=", "+"'_response': 'INCORRECT_DATE_FORMAT'";
     }
  }
//+------------------------------------------------------------------+
//|  Inform Client                                                   |
//+------------------------------------------------------------------+
void InformPullClient(Socket &pSocket,string message)
  {
// Do not use StringFormat here, as it cannot handle string arguments
// longer than sizeof(short) - problems for sending longer data, etc.
   ZmqMsg pushReply(message);
   pSocket.send(pushReply,true); // NON-BLOCKING
  }
//+------------------------------------------------------------------+
//|  OPEN NEW POSITION                                               |
//+------------------------------------------------------------------+
int DWX_PositionOpen(string _symbol,int _type,double _lots,double _price,double _SL,double _TP,string _comment,int _magic,string &zmq_ret)
  {
   int ticket,error;

   zmq_ret+="'_action': 'EXECUTION'";

// Market order valid types: ORDER_TYPE_BUY(0) | ORDER_TYPE_SELL(1)
   if(_type>1)
     {
      zmq_ret+=", "+"'_response': 'ACTION_TYPE_ERROR', 'response_value': 'INVALID_POSITION_OPEN_TYPE'";
      return(-1);
     }

   if(_lots>MaximumLotSize)
     {
      zmq_ret+=", "+"'_response': 'LOT_SIZE_ERROR', 'response_value': 'MAX_LOT_SIZE_EXCEEDED'";
      return(-1);
     }

   string valid_symbol=(_symbol=="NULL")?Symbol():_symbol;

   double vpoint  = SymbolInfoDouble(valid_symbol, SYMBOL_POINT);
   int    vdigits = (int)SymbolInfoInteger(valid_symbol, SYMBOL_DIGITS);

   double sl = 0.0;
   double tp = 0.0;

   double symbol_bid=SymbolInfoDouble(valid_symbol,SYMBOL_BID);
   double symbol_ask=SymbolInfoDouble(valid_symbol,SYMBOL_ASK);


// IMPORTANT NOTE: Single-Step stops placing for market orders: no more 2-step procedure for STP|ECN|DMA
// available int MT5 from build 821 ('Market' and 'Exchange' execution types)
   if((ENUM_ORDER_TYPE)_type==ORDER_TYPE_BUY)
     {
      if(_SL!=0.0)
         sl=NormalizeDouble(symbol_bid-_SL*vpoint,vdigits);
      if(_TP!=0.0)
         tp=NormalizeDouble(symbol_bid+_TP*vpoint,vdigits);
     }
   else
     {
      if(_SL!=0.0)
         sl=NormalizeDouble(symbol_ask+_SL*vpoint,vdigits);
      if(_TP!=0.0)
         tp=NormalizeDouble(symbol_ask-_TP*vpoint,vdigits);
     }

// Using helper object to perform transaction.
   if(!tradeHelper.PositionOpen(valid_symbol,(ENUM_ORDER_TYPE)_type,_lots,_price,sl,tp,_comment))
     {
      error=(int)tradeHelper.ResultRetcode();
      Add_Error_Description(error,zmq_ret);
      return(-1*error);
     }

   uint ret_code=tradeHelper.ResultRetcode();
   if(ret_code==TRADE_RETCODE_DONE)
     {
      // To get already opened position's id we need to find corresponding deal.
      ulong deal_id=tradeHelper.ResultDeal();
      if(HistoryDealSelect(deal_id))
        {
         ENUM_DEAL_ENTRY entry_type=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_id,DEAL_ENTRY);
         long position_ticket=HistoryDealGetInteger(deal_id,DEAL_POSITION_ID);
         // For security reason we perform checking deal entry type.
         if(PositionSelectByTicket(position_ticket) && entry_type==DEAL_ENTRY_IN)
           {
            zmq_ret+=", "+"'_magic': "+IntegerToString(PositionGetInteger(POSITION_MAGIC))
                     +", '_ticket': "+IntegerToString(position_ticket)
                     +", '_open_time': '"+TimeToString((datetime)PositionGetInteger(POSITION_TIME),TIME_DATE|TIME_SECONDS)
                     +"', '_open_price': "+DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN));

            ticket=(int)position_ticket;
           }
         else
           {
            // Immediately closed...?
            zmq_ret+=", "+"'_response': 'Position opened, but cannot be selected'";
            return(-1);
           }
        }
      else
        {
         zmq_ret+=", "+"'_response': 'Position opened, but corresponding deal cannot be selected'";
         return(-1);
        }
     }
   else
     {
      Add_Error_Description(ret_code,zmq_ret);
      return(-1*(int)ret_code);
     }

   return(ticket);
  }
//+------------------------------------------------------------------+
//| PLACE NEW PENDING ORDER                                          |
//+------------------------------------------------------------------+
int DWX_OrderOpen(string _symbol,int _type,double _lots,double _price,double _SL,double _TP,string _comment,int _magic,string &zmq_ret)
  {
   int ticket,error;

   zmq_ret+="'_action': 'EXECUTION'";

// Pending order valid types: ORDER_TYPE_BUY_LIMIT(2) | ORDER_TYPE_SELL_LIMIT(3) | ORDER_TYPE_BUY_STOP(4) | ORDER_TYPE_SELL_STOP(5).
// Also: ORDER_TYPE_BUY_STOP_LIMIT and ORDER_TYPE_SELL_STOP_LIMIT, but we leave it out int this Service version.
   if(_type<2 || _type>5)
     {
      zmq_ret+=", "+"'_response': 'ACTION_TYPE_ERROR', 'response_value': 'INVALID_PENDING_ORDER_TYPE'";
      return(-1);
     }

   if(_lots>MaximumLotSize)
     {
      zmq_ret+=", "+"'_response': 'LOT_SIZE_ERROR', 'response_value': 'MAX_LOT_SIZE_EXCEEDED'";
      return(-1);
     }

   string valid_symbol=(_symbol=="NULL")?Symbol():_symbol;
   double vpoint=SymbolInfoDouble(valid_symbol,SYMBOL_POINT);
   int    vdigits=(int)SymbolInfoInteger(valid_symbol,SYMBOL_DIGITS);

   double sl = 0.0;
   double tp = 0.0;

   if((ENUM_ORDER_TYPE)_type==ORDER_TYPE_BUY_LIMIT || (ENUM_ORDER_TYPE)_type==ORDER_TYPE_BUY_STOP)
     {
      if(_SL!=0.0)
         sl=NormalizeDouble(_price-_SL*vpoint,vdigits);
      if(_TP!=0.0)
         tp=NormalizeDouble(_price+_TP*vpoint,vdigits);
     }
   else
     {
      if(_SL!=0.0)
         sl=NormalizeDouble(_price+_SL*vpoint,vdigits);
      if(_TP!=0.0)
         tp=NormalizeDouble(_price-_TP*vpoint,vdigits);
     }

   if(!tradeHelper.OrderOpen(valid_symbol,(ENUM_ORDER_TYPE)_type,_lots,0,_price,sl,tp,0,0,_comment))
     {
      error=(int)tradeHelper.ResultRetcode();
      Add_Error_Description(error,zmq_ret);
      return(-1*error);
     }

   uint ret_code=tradeHelper.ResultRetcode();
   if(ret_code==TRADE_RETCODE_DONE)
     {
      ulong order_ticket=tradeHelper.ResultOrder();
      if(OrderSelect(order_ticket))
        {
         zmq_ret+=", "+"'_magic': "+IntegerToString(OrderGetInteger(ORDER_MAGIC))
                  +", '_ticket': "+IntegerToString(order_ticket)
                  +", '_setup_time': '"+TimeToString((datetime)OrderGetInteger(ORDER_TIME_SETUP),TIME_DATE|TIME_SECONDS)
                  +"', '_open_price': "+DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN));

         ticket=(int)order_ticket;
        }
      else
        {
         zmq_ret+=", "+"'_response': 'Pending order placed, but cannot be selected'";
         return(-1);
        }
     }
   else
     {
      Add_Error_Description(ret_code,zmq_ret);
      return(-1*(int)ret_code);
     }

   return(ticket);
  }
//+------------------------------------------------------------------+
//|  UPDATE POSITION SL/TP (SET|RESET|UPDATE)                        |
//+------------------------------------------------------------------+
bool DWX_PositionModify(int ticket,double _SL,double _TP,string &zmq_ret)
  {
   if(PositionSelectByTicket(ticket))
     {
      int dir_flag=-1;

      ENUM_POSITION_TYPE ord_type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(ord_type==POSITION_TYPE_BUY)
         dir_flag=1;

      double vpoint  = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT);
      int    vdigits = (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS);

      //If it is necessary we can remove stops.
      double sl = 0.0;
      double tp = 0.0;
      //To update|set stops
      if(_SL!=0.0)
         sl=NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN)-_SL*dir_flag*vpoint,vdigits);
      if(_TP!=0.0)
         tp=NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN)+_TP*dir_flag*vpoint,vdigits);

      if(!tradeHelper.PositionModify(ticket,sl,tp))
        {
         int error=(int)tradeHelper.ResultRetcode();
         Add_Error_Description(error,zmq_ret);
         zmq_ret+=", '_sl_attempted': "+DoubleToString(sl)+", '_tp_attempted': "+DoubleToString(tp);
         return(false);
        }
      uint ret_code=tradeHelper.ResultRetcode();
      if(ret_code==TRADE_RETCODE_DONE)
        {
         zmq_ret+=", '_sl': "+DoubleToString(sl)+", '_tp': "+DoubleToString(tp);
         return(true);
        }
      else
        {
         Add_Error_Description(ret_code,zmq_ret);
        }
     }
   else
     {
      zmq_ret+=", '_response': 'NOT_FOUND'";
     }

   return(false);
  }
//+------------------------------------------------------------------+
//|  UPDATE PENDING ORDER SL/TP (SET|RESET|UPDATE)                   |
//+------------------------------------------------------------------+
bool DWX_OrderModify(int ticket,double _SL,double _TP,string &zmq_ret)
  {
   if(OrderSelect(ticket))
     {
      int dir_flag=-1;

      ENUM_ORDER_TYPE ord_type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(ord_type==ORDER_TYPE_BUY_LIMIT || ord_type==ORDER_TYPE_BUY_STOP)
         dir_flag=1;

      double vpoint  = SymbolInfoDouble(OrderGetString(ORDER_SYMBOL), SYMBOL_POINT);
      int    vdigits = (int)SymbolInfoInteger(OrderGetString(ORDER_SYMBOL), SYMBOL_DIGITS);

      // To remove stops if necessary.
      double sl = 0.0;
      double tp = 0.0;
      // To update|set stops
      if(_SL!=0.0)
         sl=NormalizeDouble(OrderGetDouble(ORDER_PRICE_OPEN)-_SL*dir_flag*vpoint,vdigits);
      if(_TP!=0.0)
         tp=NormalizeDouble(OrderGetDouble(ORDER_PRICE_OPEN)+_TP*dir_flag*vpoint,vdigits);

      if(!tradeHelper.OrderModify(ticket,OrderGetDouble(ORDER_PRICE_OPEN),sl,tp,0,0))
        {
         int error=(int)tradeHelper.ResultRetcode();
         Add_Error_Description(error,zmq_ret);
         zmq_ret+=", '_sl_attempted': "+DoubleToString(sl)+", '_tp_attempted': "+DoubleToString(tp);
         return(false);
        }
      uint ret_code=tradeHelper.ResultRetcode();
      if(ret_code==TRADE_RETCODE_DONE)
        {
         zmq_ret+=", '_sl': "+DoubleToString(sl)+", '_tp': "+DoubleToString(tp);
         return(true);
        }
      else
        {
         Add_Error_Description(ret_code,zmq_ret);
        }
     }
   else
     {
      zmq_ret+=", '_response': 'NOT_FOUND'";
     }

   return(false);
  }
//+------------------------------------------------------------------+
//|  CLOSE AT MARKET                                                 |
//+------------------------------------------------------------------+
bool DWX_CloseAtMarket(double size,string &zmq_ret)
  {
   int retries=3;
   while(true)
     {
      retries--;
      if(retries < 0) return(false);

      if(DWX_IsTradeAllowed(30,zmq_ret)==1)
        {
         if(DWX_PositionClosePartial(size,zmq_ret))
           {
            // trade successfuly closed
            return(true);
           }
        }
     }
   return(false);
  }
//+------------------------------------------------------------------+
//|  POSITION CLOSE PARTIAL                                          |
//+------------------------------------------------------------------+
bool DWX_PositionClosePartial(double size,string &zmq_ret,int ticket=0)
  {
   int error;
   bool close_ret=false;
   if(ticket!=0)
     {
      zmq_ret += "'_action': 'CLOSE', '_ticket': " + IntegerToString(ticket);
      zmq_ret += ", '_response': 'CLOSE_PARTIAL'";
      PositionSelectByTicket(ticket);
     }

   long _ticket=PositionGetInteger(POSITION_TICKET);

   if(size<SymbolInfoDouble(PositionGetString(POSITION_SYMBOL),SYMBOL_VOLUME_MIN) || size>PositionGetDouble(POSITION_VOLUME))
     {
      size=PositionGetDouble(POSITION_VOLUME);
     }

   if(tradeHelper.PositionClosePartial(_ticket,size))
     {
      error=(int)tradeHelper.ResultRetcode();
      zmq_ret+=", "+"'_response': '"+IntegerToString(error)+"', 'response_value': '"+GetErrorDescription(error)+"'";
      return(close_ret);
     }
   uint ret_code=tradeHelper.ResultRetcode();
   if(ret_code==TRADE_RETCODE_DONE)
     {
      ulong deal_id=tradeHelper.ResultDeal();
      if(HistoryDealSelect(deal_id))
        {
         ENUM_DEAL_ENTRY entry_type=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal_id,DEAL_ENTRY);
         if(entry_type==DEAL_ENTRY_OUT)
           {
            zmq_ret+=", '_close_price': "+DoubleToString(HistoryDealGetDouble(deal_id,DEAL_PRICE))
                     +", '_close_lots': "+DoubleToString(HistoryDealGetDouble(deal_id,DEAL_VOLUME));

            close_ret=true;
           }
         else
           {
            zmq_ret+=", "+"'_response': 'Position partially closed, but corresponding deal cannot be selected'";
           }
        }
      else
        {
         zmq_ret+=", "+"'_response': 'Position partially closed, but corresponding deal cannot be selected'";
        }
     }
   else
     {
      Add_Error_Description(ret_code,zmq_ret);
     }
   return(close_ret);
  }
//+------------------------------------------------------------------+
//|  CLOSE POSITION (by Magic Number)                                |
//+------------------------------------------------------------------+
void DWX_PositionClose_Magic(int _magic,string &zmq_ret)
  {
   bool found=false;

   zmq_ret += "'_action': 'CLOSE_ALL_MAGIC'";
   zmq_ret += ", '_magic': " + IntegerToString(_magic);

   zmq_ret+=", '_responses': {";

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetTicket(i)>0 && (int)PositionGetInteger(POSITION_MAGIC)==_magic)
        {
         found=true;

         zmq_ret+=IntegerToString(PositionGetInteger(POSITION_TICKET))+": {'_symbol':'"+PositionGetString(POSITION_SYMBOL)+"'";

         DWX_CloseAtMarket(-1,zmq_ret);
         zmq_ret+=", '_response': 'CLOSE_MARKET'";

         if(i!=0)
            zmq_ret+="}, ";
         else
            zmq_ret+="}";
        }
     }

   zmq_ret+="}";
   if(found==false)
     {
      zmq_ret+=", '_response': 'NOT_FOUND'";
     }
   else
     {
      zmq_ret+=", '_response_value': 'SUCCESS'";
     }
  }
//+------------------------------------------------------------------+
//|  CLOSE POSITION (by Ticket)                                      |
//+------------------------------------------------------------------+
void DWX_PositionClose_Ticket(int _ticket,string &zmq_ret)
  {
   zmq_ret+="'_action': 'CLOSE', '_ticket': "+IntegerToString(_ticket);

   if(PositionSelectByTicket(_ticket))
     {
      DWX_CloseAtMarket(-1,zmq_ret);
      zmq_ret+=", '_response': 'CLOSE_MARKET'";
      zmq_ret+=", '_response_value': 'SUCCESS'";
     }
   else
      zmq_ret+=", '_response': 'NOT_FOUND'";
  }
//+------------------------------------------------------------------+
//|  DELETE PENDING ORDER (by Ticket)                                |
//+------------------------------------------------------------------+
void DWX_PendingOrderDelete_Ticket(int _ticket,string &zmq_ret)
  {
   zmq_ret+="'_action': 'DELETE', '_ticket': "+IntegerToString(_ticket);
   if(OrderSelect(_ticket))
     {
      if(tradeHelper.OrderDelete(_ticket))
        {
         if(tradeHelper.ResultRetcode()==TRADE_RETCODE_DONE)
           {
            zmq_ret+=", '_response': 'CLOSE_PENDING'";
            zmq_ret+=", '_response_value': 'SUCCESS'";
           }
         else
           {
            Add_Error_Description(tradeHelper.ResultRetcode(),zmq_ret);
           }
        }
      else
        {
         Add_Error_Description(tradeHelper.ResultRetcode(),zmq_ret);
        }
     }
   else
     {
      zmq_ret+=", '_response': 'NOT_FOUND'";
     }
  }
//+------------------------------------------------------------------+
//|  DELETE ALL PENDING ORDERS                                       |
//+------------------------------------------------------------------+
void DWX_PendingOrderDelete_All(string &zmq_ret)
  {
   bool found=false;

   zmq_ret+="'_action': 'DELETE_ALL'";
   zmq_ret+=", '_responses': {";
   int total_pending=OrdersTotal();
   for(int i=total_pending-1; i>=0; i--)
     {
      if(OrderGetTicket(i)>0)
        {
         found=true;
         zmq_ret+=IntegerToString(OrderGetInteger(ORDER_TICKET))+": {'_symbol':'"+OrderGetString(ORDER_SYMBOL)
                  +"', '_magic': "+IntegerToString(OrderGetInteger(ORDER_MAGIC));

         DWX_PendingOrderDelete_Ticket((int)OrderGetInteger(ORDER_TICKET),zmq_ret);
         zmq_ret+=", '_response': 'CLOSE_PENDING'";

         if(i!=0)
            zmq_ret+="}, ";
         else
            zmq_ret+="}";
        }
     }
   zmq_ret+="}";
   if(found==false)
     {
      zmq_ret+=", '_response': 'NOT_FOUND'";
     }
   else
     {
      zmq_ret+=", '_response_value': 'SUCCESS'";
     }
  }
//+------------------------------------------------------------------+
//|  CLOSE ALL POSITIONS                                             |
//+------------------------------------------------------------------+
void DWX_PositionsClose_All(string &zmq_ret)
  {
   bool found=false;
   zmq_ret+="'_action': 'CLOSE_ALL'";
   zmq_ret+=", '_responses': {";

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(PositionGetTicket(i)>0)
        {
         found=true;

         zmq_ret+=IntegerToString(PositionGetInteger(POSITION_TICKET))+": {'_symbol':'"+PositionGetString(POSITION_SYMBOL)
                  +"', '_magic': "+IntegerToString(PositionGetInteger(POSITION_MAGIC));

         DWX_CloseAtMarket(-1,zmq_ret);
         zmq_ret+=", '_response': 'CLOSE_MARKET'";

         if(i!=0)
            zmq_ret+="}, ";
         else
            zmq_ret+="}";
        }
     }
   zmq_ret+="}";

   if(found==false)
     {
      zmq_ret+=", '_response': 'NOT_FOUND'";
     }
   else
     {
      zmq_ret+=", '_response_value': 'SUCCESS'";
     }
  }
//+------------------------------------------------------------------+
//|  GET LIST OF WORKING POSITIONS                                   |
//+------------------------------------------------------------------+
void DWX_GetOpenPositions(string &zmq_ret)
  {
   bool found=false;

   zmq_ret +="'_action': 'OPEN_POSITIONS'";
   zmq_ret +=", '_positions': {";

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      found=true;

      // Check existence and select.
      if(PositionGetTicket(i)>0)
        {
         zmq_ret+=IntegerToString(PositionGetInteger(POSITION_TICKET))+": {";

         zmq_ret+="'_magic': "+IntegerToString(PositionGetInteger(POSITION_MAGIC))+", '_symbol': '"+PositionGetString(POSITION_SYMBOL)
                  +"', '_lots': "+DoubleToString(PositionGetDouble(POSITION_VOLUME))+", '_type': "+IntegerToString(PositionGetInteger(POSITION_TYPE))
                  +", '_open_price': "+DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN))+", '_open_time': '"+TimeToString(PositionGetInteger(POSITION_TIME),TIME_DATE|TIME_SECONDS)
                  +"', '_SL': "+DoubleToString(PositionGetDouble(POSITION_SL))+", '_TP': "+DoubleToString(PositionGetDouble(POSITION_TP))
                  +", '_pnl': "+DoubleToString(PositionGetDouble(POSITION_PROFIT))+", '_comment': '"+PositionGetString(POSITION_COMMENT)+"'";

         if(i!=0)
            zmq_ret+="}, ";
         else
            zmq_ret+="}";
        }
     }
   zmq_ret+="}";
  }
//+------------------------------------------------------------------+
//|  GET LIST OF PENDING ORDERS                                      |
//+------------------------------------------------------------------+
void DWX_GetPendingOrders(string &zmq_ret)
  {
   bool found=false;
   zmq_ret += "'_action': 'PENDING_ORDERS'";
   zmq_ret += ", '_orders': {";

   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      found=true;

      if(OrderGetTicket(i)>0)
        {
         zmq_ret+=IntegerToString(OrderGetInteger(ORDER_TICKET))+": {";

         zmq_ret+="'_magic': "+IntegerToString(OrderGetInteger(ORDER_MAGIC))+", '_symbol': '"+OrderGetString(ORDER_SYMBOL)
                  +"', '_lots': "+DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT))+", '_type': "+IntegerToString(OrderGetInteger(ORDER_TYPE))
                  +", '_open_price': "+DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN))+", '_SL': "+DoubleToString(OrderGetDouble(ORDER_SL))
                  +", '_TP': "+DoubleToString(OrderGetDouble(ORDER_TP))+", '_comment': '"+OrderGetString(ORDER_COMMENT)+"'";

         if(i!=0)
            zmq_ret+="}, ";
         else
            zmq_ret+="}";
        }
     }
   zmq_ret+="}";
  }
//+------------------------------------------------------------------+
//|  CHECK IF TRADE IS ALLOWED                                       |
//+------------------------------------------------------------------+
int DWX_IsTradeAllowed(int MaxWaiting_sec,string &zmq_ret)
  {
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      int StartWaitingTime=(int)GetTickCount();
      zmq_ret+=", "+"'_response': 'TRADE_CONTEXT_BUSY'";

      while(true)
        {
         if(IsStopped())
           {
            zmq_ret+=", "+"'_response_value': 'EA_STOPPED_BY_USER'";
            return(-1);
           }

         int diff=(int)(GetTickCount()-StartWaitingTime);
         if(diff>MaxWaiting_sec*1000)
           {
            zmq_ret+=", '_response': 'WAIT_LIMIT_EXCEEDED', '_response_value': "+IntegerToString(MaxWaiting_sec);
            return(-2);
           }
         // if the trade context has become free,
         if(MQLInfoInteger(MQL_TRADE_ALLOWED))
           {
            zmq_ret+=", '_response': 'TRADE_CONTEXT_NOW_FREE'";
            return(1);
           }
        }
     }
   else
     {
      return(1);
     }
  }
//+------------------------------------------------------------------+
//|  Function adding error description to zmq string message         |
//+------------------------------------------------------------------+
void Add_Error_Description(uint error_code,string &out_string)
  {
// Use 'GetErrorDescription' function already imported from https://github.com/dingmaotu/mql-zmq
   out_string+=", "+"'_response': '"+IntegerToString(error_code)+"', 'response_value': '"+GetErrorDescription(error_code)+"'";
  }
//+------------------------------------------------------------------+
